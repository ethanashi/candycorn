import SwiftUI
import UIKit

enum PhotoJournalPhase: Equatable, Sendable {
    case ready
    case camera
    case saving
    case saved
    case denied
    case unavailable
    case failed
}

struct PhotoJournalView: View {
    @Bindable var navigation: NavigationModel
    @Bindable var state: DemoState
    @State private var phase: PhotoJournalPhase = .ready
    @State private var preview: UIImage?
    @State private var savedEntry: JournalEntry?

    var body: some View {
        ScreenLayout(
            title: phase == .saved ? "Photo saved" : "Photograph a journal page",
            subtitle: "The original image stays on this device.",
            backAction: navigation.backAction(for: .journalPhoto),
            bottomInset: DesignTokens.Spacing.section
        ) {
            content
        }
        .fullScreenCover(isPresented: cameraPresented) {
            CameraPicker(onImage: save, onCancel: { phase = .ready })
                .ignoresSafeArea()
        }
    }

    @ViewBuilder private var content: some View {
        if let preview {
            Image(uiImage: preview)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius))
                .accessibilityLabel("Original journal photo")
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: DesignTokens.cardRadius)
                    .fill(DesignTokens.surfaceWarm)
                VStack(spacing: DesignTokens.Spacing.small) {
                    Image(systemName: "doc.text.viewfinder").font(.system(size: 52))
                    Text("Keep the full page inside the frame").font(TypeScale.bodyMedium)
                }
                .foregroundStyle(DesignTokens.cocoa)
            }
            .frame(height: 360)
            .accessibilityLabel("Camera frame for a journal page")
        }

        switch phase {
        case .ready:
            Button("Take photo", action: beginCapture).buttonStyle(PrimaryButtonStyle())
        case .saving:
            Button("Saving") {}.buttonStyle(PrimaryButtonStyle()).disabled(true)
        case .saved:
            StatusNotice(title: "Saved on this device", detail: "No text was extracted. The photo is the original source.", kind: .saved)
            if savedEntry != nil {
                Button("View journal") {
                    navigation.goBack(from: .journalPhoto)
                    navigation.navigate(to: .journalDetail)
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        case .denied:
            StatusNotice(title: "Camera access is off", detail: "Enable camera access in Settings, then try again. Your existing journals are unchanged.", kind: .warning)
            Button("Try again", action: beginCapture).buttonStyle(SecondaryButtonStyle())
        case .unavailable:
            StatusNotice(title: "Camera unavailable", detail: "Use an iPhone with a camera to photograph a journal page.", kind: .warning)
        case .failed:
            StatusNotice(title: "Photo could not be saved", detail: "Your existing journals are unchanged. Try again.", kind: .warning)
            Button("Try again", action: beginCapture).buttonStyle(SecondaryButtonStyle())
        case .camera:
            EmptyView()
        }
    }

    private var cameraPresented: Binding<Bool> {
        Binding(get: { phase == .camera }, set: { if !$0 && phase == .camera { phase = .ready } })
    }

    private func beginCapture() {
        guard phase != .saving else { return }
        Task {
            let status = await state.dependencies.photos.authorizationStatus()
            let permitted: Bool
            if status == .authorized {
                permitted = true
            } else if status == .notDetermined {
                permitted = await state.dependencies.photos.requestPermission()
            } else {
                permitted = false
            }
            guard permitted else {
                phase = .denied
                return
            }
            guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                phase = .unavailable
                return
            }
            phase = .camera
        }
    }

    private func save(_ image: UIImage) {
        phase = .saving
        preview = image
        Task {
            guard let data = image.jpegData(compressionQuality: 0.92), !data.isEmpty else {
                phase = .failed
                return
            }
            let width = image.cgImage?.width ?? Int(image.size.width * image.scale)
            let height = image.cgImage?.height ?? Int(image.size.height * image.scale)
            guard let attachment = await state.savePhotoJPEG(data, pixelWidth: width, pixelHeight: height) else {
                phase = .failed
                return
            }
            savedEntry = await state.createJournal(rawText: "", inputType: .photo, attachmentID: attachment.id)
            phase = savedEntry == nil ? .failed : .saved
        }
    }
}

private struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage, onCancel: onCancel) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (UIImage) -> Void
        let onCancel: () -> Void

        init(onImage: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onImage = onImage
            self.onCancel = onCancel
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true, completion: onCancel)
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard let image = info[.originalImage] as? UIImage else {
                picker.dismiss(animated: true, completion: onCancel)
                return
            }
            picker.dismiss(animated: true) { self.onImage(image) }
        }
    }
}
