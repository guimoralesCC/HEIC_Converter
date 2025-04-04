import SwiftUI
import UniformTypeIdentifiers
import CoreImage
import CoreImage.CIFilterBuiltins
import AppKit

struct ContentView: View {
    @State private var selectedFiles: [URL] = []
    @State private var outputDirectory: URL?
    @State private var isConverting = false
    @State private var conversionProgress: Double = 0
    @State private var conversionComplete = false
    @State private var totalFiles = 0
    @State private var convertedFiles = 0
    @State private var useSameFolder = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("HEIC to JPEG Converter")
                .font(.largeTitle)
                .padding(.top)
            
            VStack(alignment: .leading, spacing: 10) {
                Text("Selected Files: \(selectedFiles.count)")
                    .font(.headline)
                
                ScrollView {
                    VStack(alignment: .leading) {
                        ForEach(selectedFiles, id: \.self) { url in
                            Text(url.lastPathComponent)
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 200)
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }
            .padding(.horizontal)
            
            VStack(spacing: 10) {
                HStack(spacing: 20) {
                    Button("Select HEIC Files") {
                        selectFiles()
                    }
                    .disabled(isConverting)
                    
                    Button("Select Output Directory") {
                        selectOutputDirectory()
                    }
                    .disabled(isConverting || useSameFolder)
                    
                    Button("Convert") {
                        startConversion()
                    }
                    .disabled(selectedFiles.isEmpty || (outputDirectory == nil && !useSameFolder) || isConverting)
                }
                
                Toggle("Save to same folder as original files", isOn: $useSameFolder)
                    .disabled(isConverting)
                    .padding(.horizontal)
            }
            
            if isConverting {
                VStack {
                    ProgressView(value: conversionProgress)
                        .padding()
                    Text("Converting \(convertedFiles) of \(totalFiles)")
                }
            }
            
            if conversionComplete {
                Text("Conversion Complete!")
                    .foregroundColor(.green)
                    .padding()
            }
        }
        .padding()
        .frame(width: 600, height: 500)
    }
    
    private func selectFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if let heicType = UTType(filenameExtension: "heic") {
            panel.allowedContentTypes = [heicType]
        } else {
            // Fallback for older macOS versions
            panel.allowedFileTypes = ["heic"]
        }
        
        if panel.runModal() == .OK {
            selectedFiles = panel.urls
            conversionComplete = false
        }
    }
    
    private func selectOutputDirectory() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        
        if panel.runModal() == .OK {
            // Get security-scoped access
            let gotAccess = panel.url?.startAccessingSecurityScopedResource() ?? false
            outputDirectory = panel.url
            conversionComplete = false
            
            // Note: we'll stop accessing in the conversion function
            print("Got security access: \(gotAccess)")
        }
    }
    
    private func startConversion() {
        // Ensure we have files selected
        guard !selectedFiles.isEmpty else { return }
        
        // Determine output directory - either user selected or same as source
        var outputDir: URL?
        var accessingSecurityScopedResources = false
        
        if useSameFolder {
            // We'll use each file's directory as its output directory
            // No need to access security-scoped resources here
        } else {
            // Use the user-selected output directory
            guard let selectedDir = outputDirectory else { return }
            outputDir = selectedDir
            
            // Get security-scoped access to the output directory
            accessingSecurityScopedResources = selectedDir.startAccessingSecurityScopedResource()
            print("Accessing output directory: \(accessingSecurityScopedResources)")
        }
        
        isConverting = true
        conversionComplete = false
        totalFiles = selectedFiles.count
        convertedFiles = 0
        conversionProgress = 0
        
        let dispatchGroup = DispatchGroup()
        
        for fileURL in selectedFiles {
            dispatchGroup.enter()
            
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    // Create output file URL with jpg extension
                    let outputFileName = fileURL.deletingPathExtension().lastPathComponent + ".jpg"
                    
                    // Determine output location based on user choice
                    let outputURL: URL
                    if useSameFolder {
                        // Use the same directory as the source file
                        outputURL = fileURL.deletingLastPathComponent().appendingPathComponent(outputFileName)
                        
                        // For files in the same folder, we need to request access per file
                        fileURL.deletingLastPathComponent().startAccessingSecurityScopedResource()
                    } else {
                        // Use the user-selected output directory
                        outputURL = outputDir!.appendingPathComponent(outputFileName)
                    }
                    
                    // Load image from HEIC file
                    guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
                          let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                        throw NSError(domain: "Image loading failed", code: 1)
                    }
                    
                    // Convert to JPEG while preserving orientation
                    let imageDestination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
                    
                    guard let destination = imageDestination else {
                        throw NSError(domain: "Failed to create image destination", code: 3)
                    }
                    
                    // Get original image properties to preserve orientation
                    let originalProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
                    
                    // Set destination properties
                    let destinationProperties = [
                        kCGImageDestinationLossyCompressionQuality: 0.85
                    ] as CFDictionary
                    
                    CGImageDestinationSetProperties(destination, destinationProperties)
                    
                    // Add the image with its original properties to preserve orientation
                    CGImageDestinationAddImage(destination, cgImage, originalProperties as CFDictionary?)
                    
                    // Finalize
                    if !CGImageDestinationFinalize(destination) {
                        throw NSError(domain: "Failed to write JPEG file", code: 4)
                    }
                    
                    DispatchQueue.main.async {
                        convertedFiles += 1
                        conversionProgress = Double(convertedFiles) / Double(totalFiles)
                    }
                    
                    // If we're using the same folder, stop accessing the security-scoped resource
                    if useSameFolder {
                        fileURL.deletingLastPathComponent().stopAccessingSecurityScopedResource()
                    }
                } catch {
                    print("Error converting \(fileURL.lastPathComponent): \(error)")
                }
                
                dispatchGroup.leave()
            }
        }
        
        dispatchGroup.notify(queue: .main) {
            isConverting = false
            conversionComplete = true
            
            // Release security-scoped access when done (only if using custom output directory)
            if !useSameFolder && accessingSecurityScopedResources {
                outputDir?.stopAccessingSecurityScopedResource()
            }
        }
    }
}

// Use a simpler approach for JPEG conversion instead of custom extension
