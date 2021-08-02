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
        let filteredRequest = session.filter(request: request)
        
        if session.recordMode != .all {
            let cassette = session.cassette
            // Find interaction
            
            if let filteredRequest = filteredRequest, let interaction = session.cassette?.interactionForRequest(filteredRequest, headersToCheck: headersToCheck) {
                self.interaction = interaction
                // Forward completion
                if let completion = completion {
                    queue.async {
                        completion(interaction.responseData, interaction.response, nil)
                    }
                }
                session.finishTaskWithInteraction(self, interaction: interaction, playback: true)
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
    
            let filteredResponse : (response: Foundation.URLResponse, data: Data?)? = this.session.filter(response: response, data: data)
            
            let persistInteraction = filteredResponse != nil && filteredRequest != nil
            
            if persistInteraction {
                guard let resp = filteredResponse?.response else { return }
                let data = filteredResponse?.data
                this.interaction = Interaction(request: filteredRequest!, response: resp, responseData: data)
                guard let interaction = this.interaction else { return }
                this.session.finishTaskWithInteraction(this, interaction: interaction, playback: false)
            }
            else {
                this.session.finishTaskWithoutInteraction(this, responseData: filteredResponse?.data)
            }
        })
        task.resume()
    }
}
