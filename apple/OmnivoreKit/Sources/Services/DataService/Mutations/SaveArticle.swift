import Combine
import Foundation
import Models
import SwiftGraphQL

public enum SaveArticleStatus {
  case succeeeded
  case processing(jobId: String)
  case failed

  static func make(jobId: String, savingStatus: Enums.ArticleSavingRequestStatus) -> SaveArticleStatus {
    switch savingStatus {
    case .processing:
      return .processing(jobId: jobId)
    case .succeeded:
      return .succeeeded
    case .failed:
      return .failed
    }
  }
}

public extension Networker {
  func articleSaveStatus(jobId: String) -> AnyPublisher<SaveArticleStatus, SaveArticleError> {
    enum QueryResult {
      case saved(status: SaveArticleStatus)
      case error(errorCode: Enums.ArticleSavingRequestErrorCode)
    }

    let selection = Selection<QueryResult, Unions.ArticleSavingRequestResult> {
      try $0.on(
        articleSavingRequestError: .init { .error(errorCode: (try? $0.errorCodes().first) ?? .notFound) },
        articleSavingRequestSuccess: .init {
          .saved(
            status: try $0.articleSavingRequest(
              selection: .init {
                SaveArticleStatus.make(
                  jobId: try $0.id(),
                  savingStatus: try $0.status()
                )
              }
            )
          )
        }
      )
    }

    let query = Selection.Query {
      try $0.articleSavingRequest(id: jobId, selection: selection)
    }

    let path = appEnvironment.graphqlPath
    let headers = defaultHeaders

    return Deferred {
      Future { promise in
        send(query, to: path, headers: headers) { result in
          switch result {
          case let .success(payload):
            if let graphqlError = payload.errors {
              promise(.failure(.unknown(description: graphqlError.first.debugDescription)))
            }

            switch payload.data {
            case let .saved(status):
              promise(.success(status))
            case let .error(errorCode: errorCode):
              switch errorCode {
              case .unauthorized:
                promise(.failure(.unauthorized))
              case .notFound:
                promise(.failure(.badData))
              }
            }
          case let .failure(error):
            promise(.failure(SaveArticleError.make(from: error)))
          }
        }
      }
    }
    .receive(on: DispatchQueue.main)
    .eraseToAnyPublisher()
  }
}

public extension DataService {
  // swiftlint:disable:next line_length
  func saveArticlePublisher(pageScrapePayload: PageScrapePayload, uploadFileId: String?) -> AnyPublisher<Void, SaveArticleError> {
    enum MutationResult {
      case saved(created: Bool)
      case error(errorCode: Enums.CreateArticleErrorCode)
    }

    let preparedDocument: InputObjects.PreparedDocumentInput? = {
      if case let .html(html, title, _) = pageScrapePayload.contentType {
        return InputObjects.PreparedDocumentInput(
          document: html,
          pageInfo: InputObjects.PageInfoInput(title: OptionalArgument(title))
        )
      }
      return nil
    }()

    let input = InputObjects.CreateArticleInput(
      preparedDocument: OptionalArgument(preparedDocument),
      uploadFileId: uploadFileId != nil ? .present(uploadFileId!) : .null(),
      url: pageScrapePayload.url
    )

    let selection = Selection<MutationResult, Unions.CreateArticleResult> {
      try $0.on(
        createArticleError: .init { .error(errorCode: (try? $0.errorCodes().first) ?? .unableToParse) },
        createArticleSuccess: .init { .saved(created: try $0.created()) }
      )
    }

    let mutation = Selection.Mutation {
      try $0.createArticle(input: input, selection: selection)
    }

    let path = appEnvironment.graphqlPath
    let headers = networker.defaultHeaders

    return Deferred {
      Future { promise in
        send(mutation, to: path, headers: headers) { result in
          switch result {
          case let .success(payload):
            if let graphqlError = payload.errors {
              promise(.failure(.unknown(description: graphqlError.first.debugDescription)))
            }

            switch payload.data {
            case .saved:
              promise(.success(()))
            case let .error(errorCode: errorCode):
              switch errorCode {
              case .unauthorized:
                promise(.failure(.unauthorized))
              default:
                promise(.failure(.unknown(description: errorCode.rawValue)))
              }
            }
          case let .failure(error):
            promise(.failure(SaveArticleError.make(from: error)))
          }
        }
      }
    }
    .receive(on: DispatchQueue.main)
    .eraseToAnyPublisher()
  }

  func saveArticlePublisher(articleURL: URL) -> AnyPublisher<SaveArticleStatus, SaveArticleError> {
    saveArticlePublisher(articleURLString: articleURL.absoluteString)
  }

  func saveArticlePublisher(articleURLString: String) -> AnyPublisher<SaveArticleStatus, SaveArticleError> {
    enum MutationResult {
      case saved(status: SaveArticleStatus)
      case error(errorCode: Enums.CreateArticleSavingRequestErrorCode)
    }

    let selection = Selection<MutationResult, Unions.CreateArticleSavingRequestResult> {
      try $0.on(
        createArticleSavingRequestError: .init { .error(errorCode: (try? $0.errorCodes().first) ?? .badData) },
        createArticleSavingRequestSuccess: .init {
          .saved(
            status: try $0.articleSavingRequest(
              selection: .init {
                SaveArticleStatus.make(
                  jobId: try $0.id(),
                  savingStatus: try $0.status()
                )
              }
            )
          )
        }
      )
    }

    let mutation = Selection.Mutation {
      try $0.createArticleSavingRequest(
        input: InputObjects.CreateArticleSavingRequestInput(url: articleURLString),
        selection: selection
      )
    }

    let path = appEnvironment.graphqlPath
    let headers = networker.defaultHeaders

    return Deferred {
      Future { promise in
        send(mutation, to: path, headers: headers) { result in
          switch result {
          case let .success(payload):
            if let graphqlError = payload.errors {
              promise(.failure(.unknown(description: graphqlError.first.debugDescription)))
            }

            switch payload.data {
            case let .saved(status):
              promise(.success(status))
            case let .error(errorCode: errorCode):
              switch errorCode {
              case .unauthorized:
                promise(.failure(.unauthorized))
              case .badData:
                promise(.failure(.badData))
              }
            }
          case let .failure(error):
            promise(.failure(SaveArticleError.make(from: error)))
          }
        }
      }
    }
    .receive(on: DispatchQueue.main)
    .eraseToAnyPublisher()
  }
}
