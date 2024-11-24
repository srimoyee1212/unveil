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
        utterance.rate = 0.5 // Adjust speaking rate
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

    override init() {
        super.init()
        self.locationManager.delegate = self
        self.locationManager.desiredAccuracy = kCLLocationAccuracyBest
        self.locationManager.requestWhenInUseAuthorization()
        self.locationManager.startUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        self.location = location
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

    var body: some View {
            VStack(spacing: 16) {
                Text("Unveil History")
                    .font(.largeTitle)
                    .padding(.top)

                // Scrollable area for image, description, and chat
                ScrollView {
                    VStack(spacing: 16) {
                        if let image = capturedImage {
                            // Display captured or uploaded image
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 250)
                                .padding()
                        } else {
                            // Placeholder when no image is available
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 250)
                                .overlay(Text("Capture or Upload an image").foregroundColor(.white))
                                .padding()
                        }

                        if isLoading {
                            ProgressView("Processing...")
                                .padding()
                        } else if !buildingContext.isEmpty {
                            // Display building context and chat
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Image Context:")
                                    .font(.headline)
                                Text(buildingContext)
                                    .padding(.bottom, 10)

                                Button(action: {
                                    speechSynthesizer.speak(buildingContext)
                                }) {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .foregroundColor(.blue)
                                }

                                ForEach(chatHistory) { message in
                                    HStack {
                                        if message.role == .user {
                                            Spacer()
                                            Text(message.content)
                                                .padding()
                                                .background(Color.blue.opacity(0.8))
                                                .foregroundColor(.white)
                                                .cornerRadius(10)
                                                .frame(maxWidth: 250, alignment: .trailing)
                                            Button(action: {
                                                speechSynthesizer.speak(message.content)
                                            }) {
                                                Image(systemName: "speaker.wave.2.fill")
                                                    .foregroundColor(.white)
                                            }
                                        } else {
                                            Text(message.content)
                                                .padding()
                                                .background(Color.gray.opacity(0.3))
                                                .foregroundColor(.black)
                                                .cornerRadius(10)
                                                .frame(maxWidth: 250, alignment: .leading)
                                            Button(action: {
                                                speechSynthesizer.speak(message.content)
                                            }) {
                                                Image(systemName: "speaker.wave.2.fill")
                                                    .foregroundColor(.black)
                                            }
                                            Spacer()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 300) // Limit scrollable height
                .padding()

                if capturedImage != nil {
                    VStack {
                        // TextField for user question
                        TextField("Ask a question about the building...", text: $userQuestion)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .padding(.horizontal)

                        // Horizontal stack for Get Answer and Stop Speaking
                        HStack {
                            Button(action: {
                                dismissKeyboard()
                                fetchChatAnswer(question: userQuestion)
                            }) {
                                HStack {
                                    Image(systemName: "questionmark.circle")
                                    Text("Get Answer")
                                }
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                            }
                            .disabled(userQuestion.isEmpty || isLoading)

                            Button(action: {
                                speechSynthesizer.stopSpeaking()
                            }) {
                                HStack {
                                    Image(systemName: "stop.circle")
                                    Text("Stop Speaking")
                                }
                                .padding()
                                .background(Color.red)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                // Horizontal stack for Capture Image and Upload Image
                HStack {
                    Button(action: {
                        isCameraViewPresented = true
                    }) {
                        HStack {
                            Image(systemName: "camera")
                            Text("Capture Image")
                        }
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .sheet(isPresented: $isCameraViewPresented) {
                        CameraView(onComplete: { image, location in
                            capturedImage = image
                            isLoading = true
                            buildingContext = ""
                            userQuestion = ""
                            chatHistory = []
                            if let location = location {
                                locationString = "Location: Latitude \(location.coordinate.latitude), Longitude \(location.coordinate.longitude)"
                            } else {
                                locationString = "No location data available"
                            }
                            processImage(image: image, location: location)
                        }, locationManager: locationManager)
                    }

                    Button(action: {
                        isPhotoLibraryPresented = true
                    }) {
                        HStack {
                            Image(systemName: "photo")
                            Text("Upload Image")
                        }
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .sheet(isPresented: $isPhotoLibraryPresented) {
                        PhotoLibraryPicker(onComplete: { image, location in
                            capturedImage = image
                            isLoading = true
                            buildingContext = ""
                            userQuestion = ""
                            chatHistory = []
                            if let location = location {
                                locationString = "Location: Latitude \(location.coordinate.latitude), Longitude \(location.coordinate.longitude)"
                            } else {
                                locationString = "No location data available"
                            }
                            processImage(image: image, location: location)
                        }, locationManager: locationManager)
                    }
                }
            }
            .padding()
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

        var locationInfo = ""
        if let location = location {
            locationInfo = "Location: Latitude \(location.coordinate.latitude), Longitude \(location.coordinate.longitude)"
        }

        let url = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer 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", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "model": "llama-3.2-11b-vision-preview",
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": "What is in the image? It could be a mural, or street art, or wall art, or sculpture, or landmark in Austin unless it is a global landmark you already know of.\(locationInfo)"],
                        ["type": "image_url", "image_url": ["url": formattedImageDataURL]]
                    ]
                ]
            ],
            "temperature": 1,
            "max_tokens": 1024,
            "top_p": 1,
            "stream": false
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
                   let choices = json["choices"] as? [[String: Any]],
                   let message = choices.first?["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    DispatchQueue.main.async {
                        buildingContext = content
                        isLoading = false
                    }
                } else {
                    DispatchQueue.main.async {
                        buildingContext = "Unexpected response format."
                        isLoading = false
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    buildingContext = "Error parsing response: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }.resume()
    }

    private func fetchChatAnswer(question: String) {
        isLoading = true
        chatHistory.append(ChatMessage(role: .user, content: question))

        let url = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer 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", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "model": "llama-3.2-3b-preview",
            "messages": [
                ["role": "assistant", "content": buildingContext],
                ["role": "assistant", "content": locationString],
                ["role": "user", "content": question]
            ],
            "temperature": 1,
            "max_tokens": 512,
            "top_p": 1,
            "stream": false
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
                    chatHistory.append(ChatMessage(role: .assistant, content: "Failed to fetch the answer."))
                    isLoading = false
                }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async {
                    chatHistory.append(ChatMessage(role: .assistant, content: "No response received."))
                    isLoading = false
                }
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let message = choices.first?["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    DispatchQueue.main.async {
                        chatHistory.append(ChatMessage(role: .assistant, content: content))
                        isLoading = false
                    }
                } else {
                    DispatchQueue.main.async {
                        chatHistory.append(ChatMessage(role: .assistant, content: "Unexpected response format."))
                        isLoading = false
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    chatHistory.append(ChatMessage(role: .assistant, content: "Error parsing response: \(error.localizedDescription)"))
                    isLoading = false
                }
            }
        }.resume()
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
                
                // Try to get location from image metadata
                if let asset = info[.phAsset] as? PHAsset {
                    location = asset.location
                }
                
                // If no location in metadata, use current location as fallback
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

