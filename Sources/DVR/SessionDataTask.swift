import Foundation


final class SessionDataTask: URLSessionDataTask {

    // MARK: - Types

    typealias Completion = (Data?, Foundation.URLResponse?, NSError?) -> Void

    // MARK: - Properties

    var session: Session!
    let request: URLRequest
    let headersToCheck: [String]
    let completion: Completion?
    private let queue = DispatchQueue(label: "com.venmo.DVR.sessionDataTaskQueue", attributes: [])
    private var interaction: Interaction?

    override var response: Foundation.URLResponse? {
        return interaction?.response
    }

    override var currentRequest: URLRequest? {
        return request
    }

    // MARK: - Initializers

    init(session: Session, request: URLRequest, headersToCheck: [String] = [], completion: (Completion)? = nil) {
        self.session = session
        self.request = request
        self.headersToCheck = headersToCheck
        self.completion = completion
    }

    // MARK: - URLSessionTask

    override func cancel() {
        // Don't do anything
    }

    override func resume() {

        // apply request transformations, which could impact matching the interaction
        var filteredRequest: URLRequest? = request
        for filter in session.filters {
            guard let filtered = filter.filter(request: filteredRequest) else {
                break
            }
            filteredRequest = filtered
        }
        
        
        FindInteraction: if session.recordMode != .all {
            let cassette = session.cassette
            // Find interaction
            guard let filteredRequest = filteredRequest else {
                break FindInteraction
            }
            if let interaction = session.cassette?.interactionForRequest(filteredRequest, headersToCheck: headersToCheck) {
                self.interaction = interaction
                // Forward completion
                if let completion = completion {
                    queue.async {
                        completion(interaction.responseData, interaction.response, nil)
                    }
                }
                session.finishTask(self, interaction: interaction, playback: true)
                return
            }

            // Errors unless playbackMode = .newEpisodes
            if cassette != nil && session.recordMode != .newEpisodes {
                
                fatalError("[DVR] Invalid request. The request was not found in the cassette.")
            }

            // Errors if in playbackMode = .none
            if cassette == nil && session.recordMode == .none {
                fatalError("[DVR] No Recording Found.")
            }
            
            // Cassette is missing. Record.
            if session.recordingEnabled == false {
                fatalError("[DVR] Recording is disabled.")
            }
        }

        let task = session.backingSession.dataTask(with: request, completionHandler: { [weak self] data, response, error in

            //Ensure we have a response
            guard let response = response else {
                fatalError("[DVR] Failed to record because the task returned a nil response.")
            }

            guard let this = self else {
                fatalError("[DVR] Something has gone horribly wrong.")
            }

            // Still call the completion block so the user can chain requests while recording.
            this.queue.async {
                this.completion?(data, response, nil)
            }
            
            // Create interaction unless the response has been filtered out
            var filteredResponse = response
            var filteredData = data
            var persistInteraction = true

            for filter in this.session.filters {
                if let result = filter.filter(response: filteredResponse, withData: filteredData) {
                    (filteredResponse, filteredData) = result
                } else {
                    // do not persist the interaction if the filtered response was nil
                    persistInteraction = false
                    break
                }
            }

            if filteredRequest == nil {
                persistInteraction = false
            }
            
            if persistInteraction {
                this.interaction = Interaction(request: filteredRequest!, response: filteredResponse, responseData: filteredData)
                this.session.finishTask(this, interaction: this.interaction!, playback: false)
            } else {
                this.session.finishTask(this, responseData: filteredData, playback: true)
            }
        })
        task.resume()
    }
}

