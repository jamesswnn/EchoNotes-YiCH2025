import SwiftUI
import PencilKit
import AVFoundation
import Speech
@preconcurrency import Vision
// 1) Make PKCanvasView able to be first responder
class CanvasUIView: PKCanvasView {
    override var canBecomeFirstResponder: Bool { true }
}
// 2) A UIViewRepresentable wrapper for PencilKit
struct PencilCanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    
    
    
    class Coordinator: NSObject, PKCanvasViewDelegate {
        
        var parent: PencilCanvasView
        
        var toolPicker: PKToolPicker?
        
        
        
        init(_ parent: PencilCanvasView) {
            
            self.parent = parent
            
        }
        
        
        
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            
            parent.drawing = canvasView.drawing
            
        }
        
    }
    
    
    
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    
    
    func makeUIView(context: Context) -> PKCanvasView {
        
        let canvas = CanvasUIView()
        
        canvas.backgroundColor = .white
        
        canvas.drawingPolicy = .anyInput
        
        canvas.delegate = context.coordinator
        
        
        
        if UIApplication.shared.connectedScenes.first is UIWindowScene {
            
            let tp = PKToolPicker()
            
            tp.setVisible(true, forFirstResponder: canvas)
            
            tp.addObserver(canvas)
            
            canvas.becomeFirstResponder()
            
            context.coordinator.toolPicker = tp
            
        }
        
        
        
        return canvas
        
    }
    
    
    
    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        
        if uiView.drawing != drawing {
            
            uiView.drawing = drawing
            
        } else {
            
            drawing = uiView.drawing
            
        }
        
        if !uiView.isFirstResponder {
            
            uiView.becomeFirstResponder()
            
        }
        
    }
}


// MARK: - Speech-to-Text
@MainActor
class SpeechTranscriber: ObservableObject {
    
    // âââââ internal audio / speech objects âââââ
    private let audioEngine      = AVAudioEngine()
    private let speechRecognizer = SFSpeechRecognizer(locale: .init(identifier: "th-TH"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    // âââââ published state âââââ
    @Published var transcript: String = ""     // full running text
    
    @Published var isRecording: Bool  = false
    private var committedTranscript: String = "" // NEW: text from earlier sessions
    // buffer that holds only the current sessionâs text
    private var sessionBuffer: String = ""
    
    // MARK: Permissions
    func requestPermissions() async -> Bool {
        // 1. Speech
        let speechOK = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        guard speechOK else { return false }
        
        // 2. Mic
        let micOK = await withCheckedContinuation { cont in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { cont.resume(returning: $0) }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { cont.resume(returning: $0) }
            }
        }
        return micOK
    }
    
    func resetTranscript() {
        committedTranscript = "หินอัคนีเกิดจากการเย็นตัวและแข็งตัวของหินหนืดหรือแมกมา หินตะกอนเกิดจากการสะสมและอัดแน่นของเศษหิน แร่ หรือซากสิ่งมีชีวิตที่ทับถมกันเป็นชั้น ๆ ส่วนหินแปรเกิดจากการเปลี่ยนแปลงของหินอัคนีหรือหินตะกอนเดิมเมื่อได้รับความร้อนหรือความดันสูงจนเนื้อหินเปลี่ยนไป."
        sessionBuffer       = "หินอัคนีเกิดจากการเย็นตัวและแข็งตัวของหินหนืดหรือแมกมา หินตะกอนเกิดจากการสะสมและอัดแน่นของเศษหิน แร่ หรือซากสิ่งมีชีวิตที่ทับถมกันเป็นชั้น ๆ ส่วนหินแปรเกิดจากการเปลี่ยนแปลงของหินอัคนีหรือหินตะกอนเดิมเมื่อได้รับความร้อนหรือความดันสูงจนเนื้อหินเปลี่ยนไป."
        transcript          = "หินอัคนีเกิดจากการเย็นตัวและแข็งตัวของหินหนืดหรือแมกมา หินตะกอนเกิดจากการสะสมและอัดแน่นของเศษหิน แร่ หรือซากสิ่งมีชีวิตที่ทับถมกันเป็นชั้น ๆ ส่วนหินแปรเกิดจากการเปลี่ยนแปลงของหินอัคนีหรือหินตะกอนเดิมเมื่อได้รับความร้อนหรือความดันสูงจนเนื้อหินเปลี่ยนไป."
    }
    // MARK: Recording
    func startTranscribing() {
        Task {
            guard await requestPermissions() else {
                print("Permissions denied")
                return
            }
            
            isRecording   = true
            sessionBuffer = ""                       // start fresh buffer
            
            do {
                try configureAudioSession()
                
                let req = SFSpeechAudioBufferRecognitionRequest()
                req.shouldReportPartialResults = true
                self.request = req
                
                let input = audioEngine.inputNode
                let fmt   = input.outputFormat(forBus: 0)
                input.installTap(onBus: 0, bufferSize: 1024, format: fmt) { buf, _ in
                    req.append(buf)
                }
                
                try audioEngine.start()
                
                recognitionTask = speechRecognizer?.recognitionTask(with: req) { [weak self] res, err in
                    guard let self else { return }
                    if let res = res {
                        sessionBuffer = res.bestTranscription.formattedString
                        
                        // ð¢ publish the combination so the UI updates in real-time
                        transcript = committedTranscript
                        if !committedTranscript.isEmpty { transcript.append("\n") }
                        transcript.append(sessionBuffer)
                    }
                    if err != nil || (res?.isFinal ?? false) {
                        self.stopTranscribing()      // flush when done
                    }
                }
                
            } catch {
                print("Audio-engine error:", error)
                stopTranscribing()
            }
        }
    }
    
    func stopTranscribing() {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        request?.endAudio()
        recognitionTask?.cancel()
        isRecording = false
        
        if !sessionBuffer.isEmpty {
            if !committedTranscript.isEmpty { committedTranscript.append("\n") }
            committedTranscript.append(sessionBuffer)
            sessionBuffer = ""
            
            transcript = committedTranscript      // keep UI in sync
        }
    }
    
    // MARK: Audio-session helper
    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }
}




// 4) Main view with multi-page canvas + compare logic
struct ContentView: View {
    @State private var drawings: [PKDrawing] = [PKDrawing()]
    
    @State private var currentPage = 0
    
    @StateObject private var transcriber = SpeechTranscriber()
    
    
    
    @State private var isComparing = false
    
    @State private var comparisonResult = ""
    
    @State private var isResultFullScreen = false
    
    
    
    // ocr debug
    
    @State private var isOcrRunning = false
    
    @State private var ocrDebugOutput = ""
    
    
    
    private var pageCount: Int { drawings.count }
    
    private var pageTitle: String { "Page \(currentPage+1)/\(pageCount)" }
    
    @State private var isSummaryMode  = false      // false â Notes, true â Summary
    @State private var isSummarizing  = false
    @State private var summaryText    = ""
    
    
    @State var isPresentedSummeary: Bool = false
    
    @State var isPresentedNotes: Bool
    
    @State var isPresentedRevise = false
    
    @Environment(\.dismiss) var dismiss
    
    
    var body: some View {
        
        GeometryReader { geo in
            
            VStack{
                HStack{
                    
                    Spacer()
                    // Top toggle bar
                    HStack(spacing: 12) {
                        Button {
                            isPresentedSummeary = false
                        } label: {
                            Label("Notes", systemImage: "book.pages")
                                .frame(width: 115, height: 45)
                                .background(isSummaryMode ? Color.white : Color(hex: "013951"))
                                .foregroundColor(isSummaryMode ? .black : .white)
                                .cornerRadius(10)
                        }
                        
                        
                        Button {
                            isPresentedSummeary = true           // â Summary
                        } label: {
                            Label("Summary", systemImage: "sparkles")
                                .frame(width: 115, height: 45)
                                .background(isSummaryMode ? Color.green : Color.white)
                                .foregroundColor(isSummaryMode ? .white : .black)
                                .cornerRadius(10)
                        }
                        .fullScreenCover(isPresented: $isPresentedSummeary) {
                            SummaryView(isPresentedSummeary: isPresentedSummeary)
                        }
                        Button {
                            isPresentedRevise = true           // â Summary
                        } label: {
                            
                            Label("Revise", systemImage: "wand.and.rays.inverse")
                                .frame(width: 115, height: 45)
                                .background(isSummaryMode ? Color.green : Color.white)
                                .foregroundColor(isSummaryMode ? .white : .black)
                                .cornerRadius(10)
                        }
                        .fullScreenCover(isPresented: $isPresentedRevise) {
                            ReviseView(isPresentedSummeary: false, isPresentedRevise: isPresentedRevise)
                        }
                    }
                    Spacer()
                }
                .padding(.top, 8)
                // Hide / show tool picker when we switch modes
                .onChange(of: isSummaryMode) { showSummary in
                    setToolPicker(visible: !showSummary)   // hides in Summary, shows in Notes
                }
                
                HStack(spacing: 0) {
                    
                    
                    // âââââââââ LEFT COLUMN âââââââââ
                    VStack(spacing: 0) {
                        
                        
                        
                        Spacer(minLength: 10)
                        
                        // âââââââ------  CONDITIONAL CONTENT  ------âââââââ
                        if isSummaryMode {
                            
                            // ---------- SUMMARY MODE ----------
                            VStack(alignment: .leading, spacing: 12) {
                                Text("à¸ªà¸£à¸¸à¸à¸à¸à¹à¸£à¸µà¸¢à¸")
                                    .font(.title2).bold()
                                    .padding(.top, 8)
                                
                                ScrollView {
                                    if summaryText.isEmpty && !isSummarizing {
                                        Text("à¸à¸ âGenerate Summaryâ à¹à¸à¸·à¹à¸­à¸ªà¸£à¹à¸²à¸à¸ªà¸£à¸¸à¸")
                                            .foregroundColor(.secondary)
                                            .frame(maxWidth: .infinity, alignment: .center)
                                            .padding(.vertical, 40)
                                    } else {
                                        Text(summaryText)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding()
                                    }
                                }
                                .background(Color(.systemBackground))
                                .cornerRadius(8)
                                .shadow(radius: 4)
                                
                                Button {
                                    generateSummary()
                                } label: {
                                    HStack {
                                        if isSummarizing { ProgressView() }
                                        Text(isSummarizing ? "Generatingâ¦" : "Generate Summary")
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                                }
                                .disabled(isSummarizing)
                            }
                            .padding(.horizontal)
                            .frame(width: geo.size.width * 0.65,
                                   height: geo.size.height - 80,
                                   alignment: .top)
                            
                        } else {
                            
                            // ---------- NOTES MODE ----------
                            HStack {
                                Button { if currentPage > 0 { currentPage -= 1 } }
                                label: {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 30))
                                }
                                .disabled(currentPage == 0)
                                
                                Spacer()
                                Text(pageTitle).font(.headline)
                                Spacer()
                                
                                Button { if currentPage < pageCount - 1 { currentPage += 1 } }
                                label: {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 30))
                                }
                                .disabled(currentPage == pageCount - 1)
                                
                                Button {
                                    drawings.append(PKDrawing())
                                    currentPage = drawings.count - 1
                                } label: {
                                    Image(systemName: "plus")
                                        .font(.system(size: 30))
                                        .foregroundStyle(Color(hex: "013951"))
                                }
                            }
                            .padding(.horizontal)
                            
                            TabView(selection: $currentPage) {
                                ForEach(drawings.indices, id: \.self) { idx in
                                    PencilCanvasView(drawing: $drawings[idx])
                                        .tag(idx)
                                        .frame(width: geo.size.width * 0.65,
                                               height: geo.size.height * 0.85)
                                        .background(Color(.systemGray6))
                                        .cornerRadius(12)
                                        .shadow(radius: 5)
                                        .padding()
                                }
                            }
                            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                        }
                    }
                    // width / background stay the same
                    .frame(width: geo.size.width * 0.7, height: geo.size.height)
                    .background(Color(.systemGray5))
                    .padding(.top, -5)
                    
                    
                    
                    // Right: transcript, mic & compare
                    
                    VStack {
                        if !isResultFullScreen {
                            Spacer()
                            
                            Text("Live Transcript")
                                .font(.title2).bold()
                                .padding(.top, 70)
                            
                            ScrollView {
                                Text(transcriber.transcript)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding()
                            }
                            .background(Color(.systemBackground))
                            .cornerRadius(8)
                            .padding(.horizontal)
                            
                            Spacer()
                            
                            HStack(spacing: 20) {
                                
                                // Mic start/stop
                                Button {
                                    transcriber.isRecording
                                    ? transcriber.stopTranscribing()
                                    : transcriber.startTranscribing()
                                } label: {
                                    Image(systemName: transcriber.isRecording ? "stop.fill" : "mic.fill")
                                        .font(.system(size: 28))
                                        .padding(24)
                                        .background(Circle()
                                            .fill(transcriber.isRecording ? Color.red : Color(hex: "199a50")))
                                        .foregroundColor(.white)
                                }
                                
                                // NEW: Reset button
                                Button {
                                    transcriber.resetTranscript()
                                } label: {
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(.system(size: 24))
                                        .foregroundStyle(Color(hex: "013951"))
                                        .padding(20)
                                        .background(Circle().strokeBorder(Color(hex: "013951"), lineWidth: 2))
                                }
                            }
                            .padding(.bottom, 8)
                            
                            
                            Text(transcriber.isRecording ? "Stop" : "Start")
                                .font(.headline)
                            
                            Button {
                                compareNotesWithAudio()
                            } label: {
                                HStack {
                                    if isComparing {
                                        ProgressView()
                                    } else {
                                        Image(systemName: "magnifyingglass")
                                    }
                                    Text("Compare")
                                }
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color(hex: "013951"))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                            .padding(.horizontal)
                            .padding(.top, 12)
                        }
                        
                        // The result box stays outside the conditional to show in both modes
                        if !comparisonResult.isEmpty {
                            VStack {
                                ZStack {
                                    ScrollView {
                                        Text(comparisonResult)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding()
                                    }
                                    VStack {
                                        Spacer()
                                        HStack(alignment: .bottom) {
                                            Spacer()
                                            Button {
                                                withAnimation {
                                                    isResultFullScreen.toggle()
                                                }
                                            } label: {
                                                Image(systemName: "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left")
                                                    .font(.system(size: 19))
                                                    .foregroundStyle(.blue)
                                                    .padding(.trailing)
                                                    .padding(.bottom, 5)
                                            }
                                        }
                                    }
                                }
                            }
                            .background(Color(.systemBackground))
                            .cornerRadius(8)
                            .padding()
                            .frame(maxHeight: isResultFullScreen ? .infinity : 400)
                        }
                        
                        Spacer(minLength: 20)
                    }
                    
                    
                    .frame(width: geo.size.width*0.3, height: geo.size.height)
                    
                    .background(Color(.systemGray5))
                    .padding(.top, -100)
                    
                    
                    
                }
                
                .edgesIgnoringSafeArea(.all)
            }
            .background(Color(.systemGray5))
            
            
        }
        
    }
    /// Show or hide the PencilKit tool-picker.
    private func setToolPicker(visible: Bool) {
        // Key window (safe on iOS 15+)
        guard let window = UIApplication.shared
            .connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }),
              let picker = PKToolPicker.shared(for: window)
        else { return }
        
        // UIWindow is a UIResponder â satisfies the API
        picker.setVisible(visible, forFirstResponder: window)
    }
    
    
    
    
    
    // MARK: - Modern Vision handwriting OCR (iOS 17+)
    @available(iOS 17.0, *)
    private func performOCR(from drawing: PKDrawing) async throws -> String {
        
        // 1. Compute the drawingâs bounding box and add padding
        var bbox = drawing.bounds
        bbox = bbox.insetBy(dx: -20, dy: -20)
        if bbox.isEmpty {          // nothing drawn yet â use a default canvas
            bbox = CGRect(origin: .zero, size: .init(width: 512, height: 512))
        }
        
        // 2. Render the drawing at higher DPI so Vision âseesâ thin strokes
        let renderScale: CGFloat = 3.0         // ð try 4.0 if strokes are extremely fine
        let rendered = drawing.image(from: bbox, scale: renderScale)
        guard let cgImage = rendered.cgImage else {
            throw NSError(domain: "OCR", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Couldnât create CGImage from PKDrawing"])
        }
        
        // 3. Configure the request â Vision automatically detects handwriting & language
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel             = .accurate
        textRequest.usesLanguageCorrection       = true
        textRequest.automaticallyDetectsLanguage = true            // ð iOS 17 handwriting pipeline
        textRequest.minimumTextHeight            = 0.01            // help Vision accept small text
        
        // 4. Run the request in a continuation so we can âawaitâ the result
        return try await withCheckedThrowingContinuation { cont in
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([textRequest])
                    let observations = textRequest.results ?? []
                    
                    let result = observations
                        .compactMap { $0.topCandidates(1).first?.string }
                        .joined(separator: "\n")
                    
                    cont.resume(returning: result)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }
    
    
    
    // MARK: â OCR + API call
    
    private func compareNotesWithAudio() {
        
        Task {
            
            isComparing = true
            
            comparisonResult = ""
            
            
            
            do {
                
                let ocrText = try await performOCR(from: drawings[currentPage])
                
                let missed = try await sendToTogetherAI(
                    
                    handwritten: ocrText,
                    
                    transcript: transcriber.transcript
                    
                )
                
                comparisonResult = missed
                
            } catch {
                
                comparisonResult = "Error: \(error.localizedDescription)"
                
            }
            
            
            
            isComparing = false
            
        }
        
    }
    
    
    // MARK: â Generate summary (all pages)
    private func generateSummary() {
        Task {
            isSummarizing = true
            summaryText   = ""
            
            do {
                // ðï¸ OCR every page in parallel
                let ocrPages = try await withThrowingTaskGroup(of: String.self) { group -> [String] in
                    for drawing in drawings {
                        group.addTask { try await performOCR(from: drawing) }
                    }
                    return try await group.reduce(into: []) { $0.append($1) }
                }
                let combinedNotes = ocrPages.joined(separator: "\n\n")
                
                // ð§  call LLM for a concise summary
                let prompt = """
                สรุปเนื้อหาด้านล่างให้กระขับ ชัดเจน เป็นข้อ ๆ (ภาษาไทย):
                
                
                🎙️ถอดข้อความเสียง
                \(transcriber.transcript)
                
                คำตอบเป็นข้อสรุปเท่านั้น ไม่ต้องมีอะไรเพิ่ม
                """
                
                summaryText = try await sendToTogetherAI(
                    handwritten: combinedNotes,
                    transcript : prompt   // weâll ignore transcript param insideâ¦
                )
                
            } catch {
                summaryText = "Error: \(error.localizedDescription)"
            }
            
            isSummarizing = false
        }
    }
    
    
    
    
    // 1) Define request & response types
    
    struct ChatCompletionRequest: Encodable {
        
        struct Message: Encodable {
            
            let role: String
            
            let content: String
            
        }
        
        
        
        let model: String
        
        let messages: [Message]
        
    }
    
    
    
    struct ChatCompletionResponse: Decodable {
        
        struct Choice: Decodable {
            
            struct Message: Decodable {
                
                let role: String
                
                let content: String
                
            }
            
            let message: Message
            
        }
        
        let choices: [Choice]
        
    }
    
    
    
    
    
    // 2) New sendToTogetherAI that uses chat/completions
    
    private func sendToTogetherAI(handwritten: String, transcript: String) async throws -> String {
        
        // Replace with your actual Together.ai key
        
        let apiKey = ""
        guard !apiKey.isEmpty else {
            throw NSError(domain: "EchoNotes.Configuration", code: 1, userInfo: [NSLocalizedDescriptionKey: "AI features require a secure server-side API proxy. Do not embed API keys in the app."])
        }
        
        let url = URL(string: "https://api.together.ai/v1/chat/completions")!
        
        var request = URLRequest(url: url)
        
        request.httpMethod = "POST"
        
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        
        
        // Build up the prompt
        
        let systemPrompt = ChatCompletionRequest.Message(
            
            role: "system",
            
            content: "You are an assistant that compares handwritten notes to an audio transcript and returns only the points or mentioned in the transcript but missing from the notes."
            
        )
        
        
        
        let userPromptText = """

    Here are the handwritten notes (in Thai):



Here is the audio transcript (in Thai):



\(transcript)

Please list everything that appeared in the transcript and also expand on what they are (just a little bit) your output will always be in Thai.

"""
        
        
        
        let userPrompt = ChatCompletionRequest.Message(role: "user", content: userPromptText)
        
        
        
        let body = ChatCompletionRequest(
            
            model: "scb10x/scb10x-llama3-1-typhoon2-8b-instruct",
            
            messages: [systemPrompt, userPrompt]
            
        )
        
        
        
        request.httpBody = try JSONEncoder().encode(body)
        
        
        
        // Send the request
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        
        
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            
            throw URLError(.badServerResponse)
            
        }
        
        
        
        // Decode and return the assistant's reply
        
        let chatResponse = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        
        return chatResponse.choices.first?.message.content
        
        ?? "à¹à¸à¹à¸£à¸±à¸à¸à¸³à¸à¸­à¸à¹à¸à¹à¹à¸¡à¹à¸à¸à¹à¸à¸·à¹à¸­à¸«à¸²à¹à¸à¸à¸´à¸¥à¸à¹à¸à¸µà¹à¸à¸²à¸à¹à¸§à¹"
        
        
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        
        ContentView( isPresentedNotes: false)
    }
}
