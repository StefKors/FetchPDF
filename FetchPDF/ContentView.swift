//
//  ContentView.swift
//  FetchPDF
//
//  Created by Stef Kors on 28/04/2025.
//

import SwiftUI
import SwiftSoup

/// This is an app that finds all the links on a webpage
/// Then lists all the links in a list with a check box toggle in front of it
/// The user can then select which links they want to download and download them

struct ContentView: View {
    @AppStorage("url") private var url: String = ""
    @State private var links: [LinkItem] = []
    @State private var isLoading = false
    @State private var error: Error?
    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0
    @State private var downloadedFolderPath: URL?
    @State private var selection: Set<LinkItem> = []

    var selectedCount: Int {
        links.filter(\.isSelected).count
    }

    var body: some View {
        VStack {
            HStack {
                TextField("Enter URL", text: $url)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()

                Button("Fetch Links") {
                    Task {
                        await fetchLinks()
                    }
                }
                .disabled(url.isEmpty || isLoading)
                .buttonStyle(.borderedProminent)
                .tint(!url.isEmpty ? .primary : .blue)
            }

            if isLoading {
                ProgressView()
            } else if let error {
                Text(error.localizedDescription)
                    .foregroundStyle(.red)
            } else {
                List($links, selection: $selection) { $link in
                    HStack {
                        Toggle("", isOn: $link.isSelected)
                            .toggleStyle(.checkbox)
                        Text(link.url)
                    }
                    .tag(link)
                    .contextMenu {
                        if !link.isSelected {
                            Button("Select Links") {
                                for (index, maplink) in links.enumerated() {
                                    if selection.contains(maplink) {
                                        links[index].isSelected = true
                                    }
                                }
                            }
                        } else {
                            Button("Unselect Links") {
                                for (index, maplink) in links.enumerated() {
                                    if selection.contains(maplink) {
                                        links[index].isSelected = false
                                    }
                                }
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .listStyle(.sidebar)

                if !links.isEmpty {
                    HStack {
                        if isDownloading {
                            ProgressView(value: downloadProgress) {
                                Text("Downloading PDFs...")
                            }

                            if Int(downloadProgress) == links.count {
                                Button("Open Folder") {
                                    NSWorkspace.shared.open(.downloadsDirectory)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)
                            } else {
                                Button("Cancel") {
                                    isDownloading = false
                                    downloadProgress = 0
                                }
                            }

                        } else {
                            Button("Download (\(selectedCount)) PDFs") {
                                Task {
                                    await downloadSelectedPDFs()
                                }
                            }
                            .disabled(selectedCount == 0)
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding()
        .containerBackground(.thinMaterial, for: .window)
    }

    private func downloadSelectedPDFs() async {
        guard let baseURL = URL(string: url),
              let hostname = baseURL.host else { return }

        withAnimation(.snappy) {
            isDownloading = true
            downloadProgress = 0
        }

        let downloadsFolderURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let destinationFolderURL = downloadsFolderURL.appendingPathComponent(hostname, isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: destinationFolderURL, withIntermediateDirectories: true)

            let selectedLinks = links.filter(\.isSelected)
            var completedDownloads = 0

            for link in selectedLinks {
                guard isLoading else { break }
                guard let pdfURL = URL(string: link.url) else { continue }
                let filename = pdfURL.lastPathComponent
                let destinationURL = destinationFolderURL.appendingPathComponent(filename)
                
                do {
                    let (downloadURL, _) = try await URLSession.shared.download(from: pdfURL)
                    try FileManager.default.moveItem(at: downloadURL, to: destinationURL)

                    completedDownloads += 1
                    withAnimation(.snappy) {
                        downloadProgress = Double(completedDownloads) / Double(selectedLinks.count)
                    }
                } catch {
                    print("Failed to download PDF: \(error.localizedDescription)")
                }
            }
            withAnimation(.snappy) {
                downloadedFolderPath = destinationFolderURL
            }
        } catch {
            print("Failed to create directory: \(error.localizedDescription)")
        }
    }

    private func fetchLinks() async {
        withAnimation(.snappy) {
            isLoading = true
            error = nil
            links.removeAll()
            isDownloading = false
            downloadProgress = 0
        }

        guard let baseURL = URL(string: url) else {
            error = URLError(.badURL)
            isLoading = false
            return
        }

        var request = URLRequest(url: baseURL)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:137.0) Gecko/20100101 Firefox/137.0", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,nl;q=0.7,en;q=0.3", forHTTPHeaderField: "Accept-Language")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let htmlString = String(data: data, encoding: .utf8) else {
                throw URLError(.cannotDecodeContentData)
            }

            let document = try SwiftSoup.parse(htmlString)
            let links = try document.select("a")

            for link in links {
                let href = try link.attr("href")
                if !href.isEmpty {
                    withAnimation(.snappy) {
                        if let absoluteURL = URL(string: href, relativeTo: baseURL)?.absoluteString {
                            let isPDF = absoluteURL.lowercased().hasSuffix(".pdf")
                            self.links.append(LinkItem(url: absoluteURL, isSelected: isPDF))
                        } else if let absoluteURL = URL(string: href)?.absoluteString {
                            let isPDF = absoluteURL.lowercased().hasSuffix(".pdf")
                            self.links.append(LinkItem(url: absoluteURL, isSelected: isPDF))
                        }
                    }
                }
            }

            withAnimation(.snappy) {
                isLoading = false
            }
        } catch {
            withAnimation(.snappy) {
                self.error = error
                isLoading = false
            }
        }
    }
}

struct LinkItem: Identifiable, Hashable {
    let id = UUID()
    let url: String
    var isSelected: Bool
}

#Preview {
    ContentView()
}
