import SwiftUI
import CoreLocation
import UIKit
import Photos
import AVFoundation



class SpeechSynthesizer: ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String) {
        guard !synthesizer.isSpeaking else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.5
        synthesizer.speak(utterance)
    }

    func stopSpeaking() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }
}

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    @Published var location: CLLocation?
    @Published var isLocationReady = false  // ✅ Add this flag

    override init() {
        super.init()
        self.locationManager.delegate = self
        self.locationManager.desiredAccuracy = kCLLocationAccuracyBest
        self.locationManager.requestWhenInUseAuthorization()
        self.locationManager.startUpdatingLocation()
    }

    @Published var placemark: CLPlacemark?

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        self.location = location
        self.isLocationReady = true
        print("📍 Updated location: \(location.coordinate.latitude), \(location.coordinate.longitude)")

        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            if let placemark = placemarks?.first {
                DispatchQueue.main.async {
                    self.placemark = placemark
                    print("📌 Resolved location: \(placemark.name ?? ""), \(placemark.locality ?? ""), \(placemark.administrativeArea ?? ""), \(placemark.country ?? "")")
                }
            }
        }
    }
    func formattedAddress() -> String {
        guard let placemark = placemark else { return "" }
        let components = [placemark.name, placemark.locality, placemark.administrativeArea, placemark.country]
        return components.compactMap { $0 }.joined(separator: ", ")
    }

}


struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    let content: String

    enum Role {
        case user
        case assistant
    }
}

struct ContentView: View {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var speechSynthesizer = SpeechSynthesizer()
    @State private var isCameraViewPresented = false
    @State private var isPhotoLibraryPresented = false
    @State private var capturedImage: UIImage? = nil
    @State private var buildingContext: String = ""
    @State private var isLoading = false
    @State private var userQuestion: String = ""
    @State private var chatHistory: [ChatMessage] = []
    @State private var locationString: String = ""
    @State private var isVideoRecorderPresented = false
    @State private var capturedVideoURL: URL? = nil
    @State private var isVideoLibraryPresented = false

    var body: some View {
            VStack(spacing: 16) {
                Text("Unveil History").font(.largeTitle).padding(.top)
                ScrollView {
                    VStack(spacing: 16) {
                        if let image = capturedImage {
                            Image(uiImage: image)
                                .resizable().scaledToFit().frame(height: 250).padding()
                        } else if capturedVideoURL != nil {
                            Rectangle().fill(Color.purple.opacity(0.2)).frame(height: 250)
                                .overlay(Text("Video captured. Analyzing..."))
                        } else {
                            Rectangle().fill(Color.gray.opacity(0.3)).frame(height: 250)
                                .overlay(Text("Capture or Upload an image").foregroundColor(.white)).padding()
                        }

                        if isLoading {
                            ProgressView("Processing...").padding()
                        } else if !buildingContext.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Analysis:").font(.headline)
                                Text(buildingContext).padding(.bottom, 10)
                                Button { speechSynthesizer.speak(buildingContext) } label: {
                                    Image(systemName: "speaker.wave.2.fill").foregroundColor(.blue)
                                }
                                ForEach(chatHistory) { message in
                                    HStack {
                                        if message.role == .user {
                                            Spacer()
                                            Text(message.content).padding()
                                                .background(Color.blue.opacity(0.8)).foregroundColor(.white)
                                                .cornerRadius(10).frame(maxWidth: 250, alignment: .trailing)
                                        } else {
                                            Text(message.content).padding()
                                                .background(Color.gray.opacity(0.3)).foregroundColor(.black)
                                                .cornerRadius(10).frame(maxWidth: 250, alignment: .leading)
                                            Spacer()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }.frame(maxHeight: 300).padding()

                if capturedImage != nil || capturedVideoURL != nil {
                    VStack {
                        TextField("Ask a question about the building...", text: $userQuestion)
                            .textFieldStyle(RoundedBorderTextFieldStyle()).padding(.horizontal)
                        HStack {
                            Button(action: { dismissKeyboard(); fetchChatAnswer(question: userQuestion) }) {
                                HStack { Image(systemName: "questionmark.circle"); Text("Get Answer") }
                                    .padding().background(Color.blue).foregroundColor(.white).cornerRadius(10)
                            }.disabled(userQuestion.isEmpty || isLoading)

                            Button(action: { speechSynthesizer.stopSpeaking() }) {
                                HStack { Image(systemName: "stop.circle"); Text("Stop Speaking") }
                                    .padding().background(Color.red).foregroundColor(.white).cornerRadius(10)
                            }
                        }.padding(.horizontal)
                    }
                }

                HStack(spacing: 16) {
                    actionButton(icon: "camera", title: "Capture", color: .blue) {
                        isCameraViewPresented = true
                    }
                    .sheet(isPresented: $isCameraViewPresented) {
                        CameraView(onComplete: { image, location in
                            capturedImage = image
                            capturedVideoURL = nil
                            processImage(image: image, location: location)
                        }, locationManager: locationManager)
                    }

                    actionButton(icon: "photo", title: "Upload", color: .green) {
                        isPhotoLibraryPresented = true
                    }
                    .sheet(isPresented: $isPhotoLibraryPresented) {
                        PhotoLibraryPicker(onComplete: { image, location in
                            capturedImage = image
                            capturedVideoURL = nil
                            processImage(image: image, location: location)
                        }, locationManager: locationManager)
                    }

                    actionButton(icon: "video", title: "Record", color: .orange) {
                        isVideoRecorderPresented = true
                    }
                    .sheet(isPresented: $isVideoRecorderPresented) {
                        VideoCaptureView(onComplete: { videoURL, location in
                            capturedImage = nil
                            capturedVideoURL = videoURL
                            startVideoAnalysis(videoURL: videoURL, location: location)
                        }, locationManager: locationManager)
                    }

                    actionButton(icon: "film", title: "Upload", color: .purple) {
                        isVideoLibraryPresented = true
                    }
                    .sheet(isPresented: $isVideoLibraryPresented) {
                        VideoLibraryPicker(onComplete: { videoURL, location in
                            capturedImage = nil
                            capturedVideoURL = videoURL
                            startVideoAnalysis(videoURL: videoURL, location: location)
                        }, locationManager: locationManager)
                    }
                }
            }.padding()
        }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func processImage(image: UIImage, location: CLLocation?) {
        func resizeImage(_ image: UIImage, targetSize: CGSize) -> UIImage {
            let size = image.size
            let widthRatio = targetSize.width / size.width
            let heightRatio = targetSize.height / size.height
            let scaleFactor = min(widthRatio, heightRatio)
            let newSize = CGSize(width: size.width * scaleFactor, height: size.height * scaleFactor)
            UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
            image.draw(in: CGRect(origin: .zero, size: newSize))
            let newImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            return newImage ?? image
        }

        let resizedImage = resizeImage(image, targetSize: CGSize(width: 512, height: 512))
        guard let imageData = resizedImage.jpegData(compressionQuality: 0.8) else {
            print("Failed to convert image to JPEG data")
            isLoading = false
            return
        }
        let base64Image = imageData.base64EncodedString()
        let formattedImageDataURL = "data:image/jpeg;base64,\(base64Image)"
        let locationText = locationManager.formattedAddress().isEmpty
            ? (location != nil ? "Latitude \(location!.coordinate.latitude), Longitude \(location!.coordinate.longitude)" : "No location")
            : locationManager.formattedAddress()


        guard let url = URL(string: "https://8b61-2600-1700-6ec-9c00-28b0-94aa-919d-c355.ngrok-free.app/analyze") else {
            print("Invalid URL")
            isLoading = false
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "image_base64": formattedImageDataURL,  // ✅ Use full data URI scheme
            "location": locationText
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else {
            print("Failed to serialize JSON")
            isLoading = false
            return
        }

        request.httpBody = jsonData

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    buildingContext = "Failed to process image."
                    isLoading = false
                }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async {
                    buildingContext = "No response received."
                    isLoading = false
                }
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let content = json["response"] as? String {
                    DispatchQueue.main.async {
                        buildingContext = content
                        isLoading = false
                    }
                } else {
                    let rawString = String(data: data, encoding: .utf8) ?? "Unable to decode data"
                    print("🔴 Raw server response: \(rawString)")
                    DispatchQueue.main.async {
                        buildingContext = "Unexpected response format."
                        isLoading = false
                    }
                }
            } catch {
                let rawString = String(data: data, encoding: .utf8) ?? "Unable to decode data"
                print("❌ JSON error: \(error.localizedDescription)")
                print("🔴 Raw server response: \(rawString)")
                DispatchQueue.main.async {
                    buildingContext = "Error parsing response: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }.resume()
    }

    private func fetchChatAnswer(question: String) {
        isLoading = true

        guard let url = URL(string: "https://8b61-2600-1700-6ec-9c00-28b0-94aa-919d-c355.ngrok-free.app/chat") else {
            print("Invalid chat endpoint URL")
            isLoading = false
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: String] = [
            "context": buildingContext,
            "question": question
        ]

        guard let jsonData = try? JSONEncoder().encode(payload) else {
            print("Failed to encode chat payload")
            isLoading = false
            return
        }

        request.httpBody = jsonData

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                print("❌ Chat error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    isLoading = false
                }
                return
            }

            guard let data = data,
                  let response = try? JSONDecoder().decode([String: String].self, from: data),
                  let answer = response["response"] else {
                DispatchQueue.main.async {
                    buildingContext += "\n⚠️ Could not get chat response"
                    isLoading = false
                }
                return
            }

            DispatchQueue.main.async {
                chatHistory.append(ChatMessage(role: .user, content: question))
                chatHistory.append(ChatMessage(role: .assistant, content: answer))
                userQuestion = ""
                isLoading = false
            }
        }.resume()
    }

    
    
    private func startVideoAnalysis(videoURL: URL, location: CLLocation?) {
        isLoading = true
        buildingContext = "Processing video..."

        let boundary = UUID().uuidString
        guard let serverURL = URL(string: "https://8b61-2600-1700-6ec-9c00-28b0-94aa-919d-c355.ngrok-free.app/analyze_video") else {
            print("Invalid video endpoint URL")
            self.isLoading = false
            return
        }

        var request = URLRequest(url: serverURL)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        let locationText = location != nil ? "Latitude \(location!.coordinate.latitude), Longitude \(location!.coordinate.longitude)" : "No location"
        let filename = videoURL.lastPathComponent
        let mimetype = "video/mp4"

        // Add video file to body
        if let videoData = try? Data(contentsOf: videoURL) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"video\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: \(mimetype)\r\n\r\n".data(using: .utf8)!)
            body.append(videoData)
            body.append("\r\n".data(using: .utf8)!)
        }

        // Add location to body
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"location\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(locationText)\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        URLSession.shared.uploadTask(with: request, from: body) { data, response, error in
            if let error = error {
                print("Video upload failed: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    buildingContext = "Failed to upload video."
                    isLoading = false
                }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async {
                    buildingContext = "No response from server."
                    isLoading = false
                }
                return
            }

            if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let summary = json["summary"] as? String {
                DispatchQueue.main.async {
                    buildingContext = summary
                    isLoading = false
                }
            } else {
                let raw = String(data: data, encoding: .utf8) ?? "Unable to decode server response."
                print("❌ Server response: \(raw)")
                DispatchQueue.main.async {
                    buildingContext = "Unexpected server response."
                    isLoading = false
                }
            }
        }.resume()
    }

}

struct PhotoLibraryPicker: UIViewControllerRepresentable {
    var onComplete: (UIImage, CLLocation?) -> Void
    @ObservedObject var locationManager: LocationManager

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        return Coordinator(self)
    }

    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: PhotoLibraryPicker

        init(_ parent: PhotoLibraryPicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                var location: CLLocation?
                if let asset = info[.phAsset] as? PHAsset {
                    location = asset.location
                }
                if location == nil {
                    location = parent.locationManager.location
                }
                parent.onComplete(image, location)
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

struct VideoLibraryPicker: UIViewControllerRepresentable {
    var onComplete: (URL, CLLocation?) -> Void
    @ObservedObject var locationManager: LocationManager

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        picker.mediaTypes = ["public.movie"]
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        return Coordinator(self)
    }

    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: VideoLibraryPicker

        init(_ parent: VideoLibraryPicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let videoURL = info[.mediaURL] as? URL {
                let location = parent.locationManager.location
                parent.onComplete(videoURL, location)
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

// MARK: - Reusable Button UI for Actions

func actionButton(icon: String, title: String, color: Color, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title2)
            Text(title)
                .font(.footnote)
                .multilineTextAlignment(.center)
        }
        .frame(width: 80, height: 80)
        .background(color)
        .foregroundColor(.white)
        .cornerRadius(12)
    }
}

