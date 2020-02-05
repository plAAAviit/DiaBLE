import Foundation


struct NightscoutServer {
    let siteURL: String
    let token: String
}


class Nightscout {

    var server: NightscoutServer
    
    /// Main app delegate
    var main: MainDelegate!

    init(_ server: NightscoutServer) {
        self.server = server
    }


    // https://github.com/ps2/rileylink_ios/blob/master/NightscoutUploadKit/NightscoutUploader.swift
    // https://github.com/JohanDegraeve/xdripswift/blob/master/xdrip/Managers/NightScout/NightScoutUploadManager.swift

    // TODO: query parameters
    func request(endpoint: String = "", query: String = "", handler: @escaping (Data?, URLResponse?, Error?, [Any]) -> Void) {
        var url = "https://\(server.siteURL)"

        if !endpoint.isEmpty { url += ("/" + endpoint) }
        if !query.isEmpty    { url += ("?" + query) }

        var request = URLRequest(url: URL(string: url)!)
        main?.debugLog("Nightscout: URL request: \(request.url!.absoluteString)")
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let data = data { self.main?.debugLog("Nightscout: response data: \(data.string)")
                if let json = try? JSONSerialization.jsonObject(with: data) {
                    if let array = json as? [Any] {
                        DispatchQueue.main.async {
                            handler(data, response, error, array)
                        }
                    }
                }
            }
        }.resume()
    }


    func read(handler: (([Glucose]) -> ())? = nil) {
        request(endpoint: "api/v1/entries.json", query: "count=100") {data, response, error, array in
            var values = [Glucose]()
            for item in array {
                if let dict = item as? [String: Any] {
                    if let value = dict["sgv"] as? Int, let id = dict["date"] as? Int, let device = dict["device"] as? String {
                        values.append(Glucose(value, id: id, date: Date(timeIntervalSince1970: Double(id)/1000), source: device))
                    }
                }
            }
            if values.count > 0 {
                DispatchQueue.main.async {
                    self.main.history.nightscoutValues = values
                    handler?(values)
                }
            }
        }
    }


    func post(_ jsonObject: Any, endpoint: String = "", handler: (((Data?, URLResponse?, Error?) -> Void))? = nil) {
        let json = try! JSONSerialization.data(withJSONObject: jsonObject, options: [])
        var request = URLRequest(url: URL(string: "https://\(server.siteURL)/\(endpoint)")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField:"Content-Type")
        request.setValue("application/json", forHTTPHeaderField:"Accept")
        request.setValue(server.token.sha1,  forHTTPHeaderField:"api-secret")
        URLSession.shared.uploadTask(with: request, from: json) { data, response, error in
            if let error = error {
                self.main?.log("Nightscout: error: \(error.localizedDescription)")
            }
            if let response = response as? HTTPURLResponse {
                let status = response.statusCode
                if status == 401 {
                    self.main?.log("Nightscout: POST not authorized")
                }
                if let data = data {
                    self.main?.debugLog("Nightscout: post \((200..<300).contains(status) ? "success" : "error") (\(status)): \(data.string)")
                }
            }
            DispatchQueue.main.async {
                handler?(data, response, error)
            }
        }.resume()
    }


    func post(entries: [Glucose], handler: (((Data?, URLResponse?, Error?) -> Void))? = nil) {

        let dictionaryArray = entries.map { [
            "type": "sgv",
            "dateString": ISO8601DateFormatter().string(from: $0.date),
            "date": Int64(($0.date.timeIntervalSince1970 * 1000.0).rounded()),
            "sgv": $0.value,
            "device": $0.source // TODO
            // "direction": "NOT COMPUTABLE", // TODO
            ]
        }
        post(dictionaryArray, endpoint: "api/v1/entries") { data, response, error in
            DispatchQueue.main.async {
                handler?(data, response, error)
            }
        }
    }


    func delete(endpoint: String = "api/v1/entries", query: String = "", handler: (((Data?, URLResponse?, Error?) -> Void))? = nil) {
        var url = "https://\(server.siteURL)"

        if !endpoint.isEmpty { url += ("/" + endpoint) }
        if !query.isEmpty    { url += ("?" + query) }

        var request = URLRequest(url: URL(string: url)!)
        main?.debugLog("Nightscout: DELETE request: \(request.url!.absoluteString)")
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField:"Content-Type")
        request.setValue("application/json", forHTTPHeaderField:"Accept")
        request.setValue(server.token.sha1,  forHTTPHeaderField:"api-secret")
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                self.main?.log("Nightscout: error: \(error.localizedDescription)")
            }
            if let response = response as? HTTPURLResponse {
                let status = response.statusCode
                if status == 401 {
                    self.main?.log("Nightscout: DELETE not authorized")
                }
                if let data = data {
                    self.main?.debugLog("Nightscout: delete \((200..<300).contains(status) ? "success" : "error") (\(status)): \(data.string)")
                }
            }
            DispatchQueue.main.async {
                handler?(data, response, error)
            }
        }.resume()
    }


    // TODO:
    func test(handler: (((Data?, URLResponse?, Error?) -> Void))? = nil) {
        var request = URLRequest(url: URL(string: "https://\(server.siteURL)/api/v1/entries.json?token=\(server.token)")!)
        request.setValue("application/json", forHTTPHeaderField:"Content-Type")
        request.setValue("application/json", forHTTPHeaderField:"Accept")
        request.setValue(server.token.sha1, forHTTPHeaderField:"api-secret")
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                self.main?.log("Nightscout: authorization error: \(error.localizedDescription)")
            } else {
                if let response = response as? HTTPURLResponse {
                    let status = response.statusCode
                    if status == 401 {
                        self.main?.log("Nightscout: not authorized")
                    }
                    if let data = data {
                        self.main?.debugLog("Nightscout: authorization \((200..<300).contains(status) ? "success" : "error") (\(status)): \(data.string)")
                    }
                }
            }
            DispatchQueue.main.async {
                handler?(data, response, error)
            }
        }.resume()
    }
}
