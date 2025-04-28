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

    var selectedCount: Int {
        links.filter(\.isSelected).count
    }

    var body: some View {
        VStack {
            HStack {
                if let _ = URL(string: url) {
                    Image(systemName: "checkmark.seal.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                        .foregroundStyle(.green)
                } else if url.isEmpty {
                    Image(systemName: "circle.dotted")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: "xmark.circle.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                        .foregroundStyle(.red)
                }

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
            }

            if isLoading {
                ProgressView()
            } else if let error {
                Text(error.localizedDescription)
                    .foregroundStyle(.red)
            } else {
                List {
                    ForEach($links) { $link in
                        HStack {
                            Toggle("", isOn: $link.isSelected)
                                .toggleStyle(.checkbox)
                            Text(link.url)
                        }
                    }
                }

                if !links.isEmpty {
                    VStack {
                        if isDownloading {
                            ProgressView(value: downloadProgress) {
                                Text("Downloading PDFs...")
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
                    .padding(.vertical)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding()
    }

    private func downloadSelectedPDFs() async {
        guard let baseURL = URL(string: url),
              let hostname = baseURL.host else { return }

        isDownloading = true
        downloadProgress = 0

        let downloadsFolderURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let destinationFolderURL = downloadsFolderURL.appendingPathComponent(hostname, isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: destinationFolderURL, withIntermediateDirectories: true)

            let selectedLinks = links.filter(\.isSelected)
            var completedDownloads = 0

            for link in selectedLinks {
                guard let pdfURL = URL(string: link.url) else { continue }
                let filename = pdfURL.lastPathComponent
                let destinationURL = destinationFolderURL.appendingPathComponent(filename)

                do {
                    let (downloadURL, _) = try await URLSession.shared.download(from: pdfURL)
                    try FileManager.default.moveItem(at: downloadURL, to: destinationURL)

                    completedDownloads += 1
                    downloadProgress = Double(completedDownloads) / Double(selectedLinks.count)
                } catch {
                    print("Failed to download PDF: \(error.localizedDescription)")
                }
            }
        } catch {
            print("Failed to create directory: \(error.localizedDescription)")
        }

        isDownloading = false
        downloadProgress = 0
    }

    private func fetchLinks() async {
        isLoading = true
        error = nil
        links.removeAll()

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
                    if let absoluteURL = URL(string: href, relativeTo: baseURL)?.absoluteString {
                        let isPDF = absoluteURL.lowercased().hasSuffix(".pdf")
                        self.links.append(LinkItem(url: absoluteURL, isSelected: isPDF))
                    } else if let absoluteURL = URL(string: href)?.absoluteString {
                        let isPDF = absoluteURL.lowercased().hasSuffix(".pdf")
                        self.links.append(LinkItem(url: absoluteURL, isSelected: isPDF))
                    }
                }
            }

            isLoading = false
        } catch {
            self.error = error
            isLoading = false
        }
    }
}

struct LinkItem: Identifiable {
    let id = UUID()
    let url: String
    var isSelected: Bool
}

#Preview {
    ContentView()
}
