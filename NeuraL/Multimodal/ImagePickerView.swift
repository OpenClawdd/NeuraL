//
//  ImagePickerView.swift
//  NeuraL
//
//  Phase 6.1 — Image Picker & Camera UI for Vision Models
//
//  Provides a PhotosPicker and camera capture interface for attaching
//  images to chat messages. Images are resized and compressed before
//  being stored as ImageAttachment objects.
//

import SwiftUI
import PhotosUI

// MARK: - Image Picker Button

/// A button that shows a photos picker sheet for attaching images to messages.
struct ImagePickerButton: View {
    let onImageSelected: (ImageAttachment) -> Void

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showSourceChoice = false

    var body: some View {
        Menu {
            Button {
                showCamera = true
            } label: {
                Label("Take Photo", systemImage: "camera")
            }

            PhotosPicker(
                selection: $selectedPhoto,
                matching: .images,
                photoLibrary: .shared()
            ) {
                Label("Photo Library", systemImage: "photo.on.rectangle")
            }
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.title3)
                .foregroundStyle(.blue)
        }
        .onChange(of: selectedPhoto) { _, newItem in
            guard let newItem = newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let attachment = ImageAttachment.from(data: data) {
                    onImageSelected(attachment)
                }
            }
            selectedPhoto = nil
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraCaptureView { image in
                if let attachment = ImageAttachment.from(image) {
                    onImageSelected(attachment)
                }
            }
        }
    }
}

// MARK: - Camera Capture View

/// A simple camera capture view using UIImagePickerController.
struct CameraCaptureView: UIViewControllerRepresentable {
    let onImageCaptured: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImageCaptured: onImageCaptured, dismiss: dismiss)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImageCaptured: (UIImage) -> Void
        let dismiss: DismissAction

        init(onImageCaptured: @escaping (UIImage) -> Void, dismiss: DismissAction) {
            self.onImageCaptured = onImageCaptured
            self.dismiss = dismiss
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                onImageCaptured(image)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}

// MARK: - Image Attachment Preview

/// A small thumbnail view for an image attached to a message.
struct ImageAttachmentThumbnail: View {
    let attachment: ImageAttachment
    let isRemovable: Bool
    let onRemove: (() -> Void)?

    init(attachment: ImageAttachment, isRemovable: Bool = false, onRemove: (() -> Void)? = nil) {
        self.attachment = attachment
        self.isRemovable = isRemovable
        self.onRemove = onRemove
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let thumbnail = attachment.thumbnailImage {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 60, height: 60)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
            }

            if isRemovable {
                Button {
                    onRemove?()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.white, .red)
                }
                .offset(x: 4, y: -4)
            }
        }
    }
}

// MARK: - Attached Images Bar

/// A horizontal scroll of image thumbnails shown above the input bar
/// when images are attached to the current message.
struct AttachedImagesBar: View {
    let attachments: [ImageAttachment]
    let onRemove: (UUID) -> Void

    var body: some View {
        if !attachments.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(attachments) { attachment in
                        ImageAttachmentThumbnail(
                            attachment: attachment,
                            isRemovable: true,
                            onRemove: { onRemove(attachment.id) }
                        )
                    }
                }
                .padding(.horizontal, 12)
            }
            .padding(.vertical, 6)
        }
    }
}

// MARK: - Message Image View

/// A view for displaying an image within a chat bubble.
struct MessageImageView: View {
    let attachment: ImageAttachment

    var body: some View {
        if let thumbnail = attachment.thumbnailImage {
            Image(uiImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 240, maxHeight: 200)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
                .contextMenu {
                    Button {
                        // Save to photos
                        UIImageWriteToSavedPhotosAlbum(thumbnail, nil, nil, nil)
                    } label: {
                        Label("Save Image", systemImage: "square.and.arrow.down")
                    }
                }
        }
    }
}
