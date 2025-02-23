import SwiftUI
import Foundation
import Dispatch

struct ContentView: View {
    @State private var logText: String = "Welcome to Timeleap!\n"
    @State private var statusText: String = "Status: Idle\n"
    @State private var monitoringText: String = "Monitoring Output...\n"
    
    @State private var isWorkerRunning: Bool = false
    @State private var isBrokerRunning: Bool = false
    @State private var releaseVersion: String = "v0.14.0-alpha.2"
    @State private var isTimeleapInstalled: Bool = false
    @State private var isSetupComplete: Bool = false
    @State private var logLevel: String = "info"
    @State private var systemName: String = "Timeleap"
    @State private var bindAddress: String = "0.0.0.0:9123"
    @State private var brokerURI: String = "ws://localhost:9123"
    @State private var publicKey: String = "publicKey"
    @State private var cpus: String = "1"
    @State private var gpus: String = "0"
    @State private var ram: String = "1024"
    @State private var rpc: String = "https://arbitrum.llamarpc.com"
    
    @State private var showConfiguration: Bool = false
    
    // Timer to periodically check node status
    @State private var nodeStatusTimer: Timer?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Timeleap Setup").font(.title).padding(.top, 20)
            
            // Add a TextField for the release version
            HStack {
                Text("Release Version:")
                TextField("Enter release version", text: $releaseVersion)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 200)
                    .onChange(of: releaseVersion) {
                        checkTimeleapInstallation()
                    }
            }
            
       
            
            HStack(spacing: 30) {
                Button(action: { downloadTimeleapCLI() }) {
                    Text("Download Timeleap CLI")
                        .font(.headline)
                        .padding()
                        .background(isTimeleapInstalled && isMatchingVersion() ? Color.gray : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .disabled(isTimeleapInstalled && isMatchingVersion())
                
                // Setup Timeleap Button
                if !isSetupComplete {
                    Button(action: { setupTimeleap() }) {
                        Text("Setup Timeleap")
                            .font(.headline)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
                
                Button(action: { toggleBrokerNode() }) {
                    Text(isBrokerRunning ? "Broker Node Running" : "Start Broker Node")
                        .font(.headline)
                        .padding()
                        .background(isBrokerRunning ? Color.green : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                
                Button(action: { toggleWorkerNode() }) {
                    Text(isWorkerRunning ? "Worker Node Running" : "Start Worker Node")
                        .font(.headline)
                        .padding()
                        .background(isWorkerRunning ? Color.green : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                
                // Configuration Button
                Button(action: { showConfiguration.toggle() }) {
                    Text("Show Configuration")
                        .font(.headline)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .sheet(isPresented: $showConfiguration) {
                    ConfigurationView(
                        logLevel: $logLevel,
                        systemName: $systemName,
                        bindAddress: $bindAddress,
                        brokerURI: $brokerURI,
                        publicKey: $publicKey,
                        cpus: $cpus,
                        gpus: $gpus,
                        ram: $ram,
                        rpc: $rpc,
                        updateConfYaml: updateConfYaml,
                        closeConfiguration: { showConfiguration = false }
                    )
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            VStack(alignment: .leading, spacing: 10) {
                Text("Logs").font(.headline)
                TextEditor(text: $logText)
                    .frame(height: 150)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(10)
            }
            
            VStack(alignment: .leading, spacing: 10) {
                Text("Monitoring").font(.headline)
                TextEditor(text: $monitoringText)
                    .frame(height: 240)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(10)
            }
            Button(action: { clearLogs() }) {
                Text("Clear Logs")
                    .font(.headline)
                    .padding()
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding()
        .onAppear {
            monitorLogs()
            startNodeStatusTimer()
            checkTimeleapInstallation()
            loadConfYaml() // Load conf.yaml values
            
            // Load the setup completion state from UserDefaults
            self.isSetupComplete = checkSetupFiles()
        }
        .onDisappear {
            stopNodeStatusTimer()
        }
    }
    
    // MARK: - Functions
    
    func startNodeStatusTimer() {
        nodeStatusTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            checkNodeStatus()
        }
    }
    
    func stopNodeStatusTimer() {
        nodeStatusTimer?.invalidate()
        nodeStatusTimer = nil
    }
    
    func checkNodeStatus() {
        let brokerStatus = runShellCommandAndReturnOutput("pgrep -f 'timeleap broker'")
        let workerStatus = runShellCommandAndReturnOutput("pgrep -f 'timeleap worker'")
        
        DispatchQueue.main.async {
            self.isBrokerRunning = !brokerStatus.isEmpty
            self.isWorkerRunning = !workerStatus.isEmpty
        }
    }
    
    func downloadTimeleapCLI() {
        // Update logText immediately on the main thread
        DispatchQueue.main.async {
            self.logText += "Downloading Timeleap CLI...\n"
        }

        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path
        let timeleapDir = "\(homeDirectory)/timeleap"
        let timeleapPath = "\(homeDirectory)/.local/bin/timeleap"

        let osName: String
    #if os(macOS)
        osName = "darwin"
    #elseif os(Linux)
        osName = "linux"
    #elseif os(Windows)
        osName = "windows"
    #else
        osName = "unknown"
    #endif

        let architecture = ProcessInfo.processInfo.machineHardwareName
        let archName: String
        if architecture.contains("arm64") {
            archName = "arm64"
        } else if architecture.contains("x86_64") || architecture.contains("amd64") {
            archName = "amd64"
        } else {
            archName = "unknown"
        }

        // Use the releaseVersion state variable in the URL
        let timeleapURL = "https://github.com/TimeleapLabs/timeleap/releases/download/\(releaseVersion)/timeleap.\(osName).\(archName)"
        DispatchQueue.main.async {
            self.logText += "Download URL: \(timeleapURL)\n"
        }

        // Run the download on a background thread
        DispatchQueue.global().async {
            // Ensure the directory exists
            self.runShellCommand("mkdir -p \(timeleapDir)")
            DispatchQueue.main.async {
                self.logText += "Ensuring directory exists: \(timeleapDir)...\n"
            }

            // Run the curl command
            let curlCommand = "curl -L -o \(timeleapPath) \(timeleapURL)"
            DispatchQueue.main.async {
                self.logText += "Running command: \(curlCommand)\n"
            }
            let curlOutput = self.runShellCommandAndReturnOutput(curlCommand)
            DispatchQueue.main.async {
                self.logText += "curl output: \(curlOutput)\n"
            }

            // Check if the download was successful
            if FileManager.default.fileExists(atPath: timeleapPath) {
                self.runShellCommand("chmod +x \(timeleapPath)")
                DispatchQueue.main.async {
                    self.logText += "✅ Timeleap CLI downloaded and made executable!\n"
                }
            } else {
                DispatchQueue.main.async {
                    self.logText += "❌ ERROR: Failed to download Timeleap CLI.\n"
                }
            }
        }
    }
    
    func checkTimeleapInstallation() {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path
        let timeleapPath = "\(homeDirectory)/.local/bin/timeleap"
        
        if FileManager.default.fileExists(atPath: timeleapPath) {
            let versionOutput = runShellCommandAndReturnOutput("\(timeleapPath) --version")
            let installedVersion = "v" + versionOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            
            isTimeleapInstalled = true
            if installedVersion == releaseVersion {
                logText += "✅ Timeleap CLI is already installed and matches the release version.\n"
            } else {
                logText += "⚠️ Timeleap CLI is installed but the version does not match.\n"
            }
        } else {
            isTimeleapInstalled = false
            logText += "Timeleap CLI is not installed.\n"
        }
    }
    
    func isMatchingVersion() -> Bool {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path
        let timeleapPath = "\(homeDirectory)/.local/bin/timeleap"
        
        if FileManager.default.fileExists(atPath: timeleapPath) {
            let versionOutput = runShellCommandAndReturnOutput("\(timeleapPath) --version")
            let installedVersion = "v" + versionOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            return installedVersion == releaseVersion
        }
        return false
    }
    
    // Toggle Broker Node
    func toggleBrokerNode() {
        let debugOutput = runShellCommandAndReturnOutput("pgrep -f 'timeleap broker'")
        self.logText += "Broker PIDs at toggle: \(debugOutput)\n"
        
        if isBrokerRunning {
            isBrokerRunning = false // Update state immediately
            stopBrokerNode()
        } else {
            isBrokerRunning = true // Update state immediately
            startBrokerNode()
        }
    }
    
    // Toggle Worker Node
    func toggleWorkerNode() {
        if isWorkerRunning {
            isWorkerRunning = false // Update state immediately
            stopWorkerNode()
        } else {
            isWorkerRunning = true // Update state immediately
            startWorkerNode()
        }
    }
    
    // Start Broker Node
    func startBrokerNode() {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path
        let timeleapDir = "\(homeDirectory)/timeleap"
        let timeleapPath = "\(homeDirectory)/.local/bin/timeleap"
        let logFilePath = "\(timeleapDir)/timeleap.log"
        
        DispatchQueue.global().async {
            DispatchQueue.main.async {
                self.statusText += "Starting Broker Node...\n"
            }
            
            // Run broker in background
            self.runShellCommand("cd \(timeleapDir) && \(timeleapPath) broker >> \(logFilePath) 2>&1 &")
            
            // Wait for the broker process to start
            var retryCount = 5
            while retryCount > 0 {
                let output = self.runShellCommandAndReturnOutput("pgrep -f 'timeleap broker'").trimmingCharacters(in: .whitespacesAndNewlines)
                if !output.isEmpty {
                    // Broker process is running
                    DispatchQueue.main.async {
                        self.isBrokerRunning = true
                        self.statusText += "Broker Node started.\n"
                    }
                    return
                }
                Thread.sleep(forTimeInterval: 1) // Wait before checking again
                retryCount -= 1
            }
            
            // If the broker process didn't start
            DispatchQueue.main.async {
                self.statusText += "❌ ERROR: Broker Node failed to start.\n"
            }
        }
    }
    
    // Stop Broker Node
    func stopBrokerNode() {
        Foundation.DispatchQueue.global().async {
            Foundation.DispatchQueue.main.async {
                self.statusText += "Stopping Broker Node...\n"
            }
            
            // Kill the process
            self.runShellCommand("pkill -f 'timeleap broker'")
            
            // Ensure the process is actually stopped
            var retryCount = 5
            while retryCount > 0 {
                let output = self.runShellCommandAndReturnOutput("pgrep -f 'timeleap broker'").trimmingCharacters(in: .whitespacesAndNewlines)
                if output.isEmpty {
                    break // Process is fully stopped
                }
                Thread.sleep(forTimeInterval: 1) // Wait before checking again
                retryCount -= 1
            }
            
            // Confirm it's stopped before updating the UI
            Foundation.DispatchQueue.main.async {
                self.isBrokerRunning = false
                self.statusText += "Broker Node stopped.\n"
            }
        }
    }
    
    // Start Worker Node
    func startWorkerNode() {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path
        let timeleapDir = "\(homeDirectory)/timeleap"
        let timeleapPath = "\(homeDirectory)/.local/bin/timeleap"
        let logFilePath = "\(timeleapDir)/timeleap.log"
        
        DispatchQueue.global().async {
            DispatchQueue.main.async {
                self.statusText += "Starting Worker Node...\n"
            }
            
            // Run worker in background
            self.runShellCommand("cd \(timeleapDir) && \(timeleapPath) worker >> \(logFilePath) 2>&1 &")
            
            // Wait for the worker process to start
            var retryCount = 5
            while retryCount > 0 {
                let output = self.runShellCommandAndReturnOutput("pgrep -f 'timeleap worker'").trimmingCharacters(in: .whitespacesAndNewlines)
                if !output.isEmpty {
                    // Worker process is running
                    DispatchQueue.main.async {
                        self.isWorkerRunning = true
                        self.statusText += "Worker Node started.\n"
                    }
                    return
                }
                Thread.sleep(forTimeInterval: 1) // Wait before checking again
                retryCount -= 1
            }
            
            // If the worker process didn't start
            DispatchQueue.main.async {
                self.statusText += "❌ ERROR: Worker Node failed to start.\n"
            }
        }
    }
    
    // Stop Worker Node
    func stopWorkerNode() {
        DispatchQueue.global().async {
            DispatchQueue.main.async {
                self.statusText += "Stopping Worker Node...\n"
            }
            
            // Kill the process
            self.runShellCommand("pkill -f 'timeleap worker'")
            
            // Ensure the process is actually stopped
            var retryCount = 5
            while retryCount > 0 {
                let output = self.runShellCommandAndReturnOutput("pgrep -f 'timeleap worker'").trimmingCharacters(in: .whitespacesAndNewlines)
                if output.isEmpty {
                    break // Process is fully stopped
                }
                Thread.sleep(forTimeInterval: 1) // Wait before checking again
                retryCount -= 1
            }
            
            // Confirm it's stopped before updating the UI
            DispatchQueue.main.async {
                self.isWorkerRunning = false
                self.statusText += "Worker Node stopped.\n"
            }
        }
    }
    
    func clearLogs() {
        logText = ""
        statusText = "Status: Idle\n"
        monitoringText = "Monitoring Output...\n"
        
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path
        let timeleapDir = "\(homeDirectory)/timeleap"
        let logFilePath = "\(timeleapDir)/timeleap.log"
        
        do {
            if FileManager.default.fileExists(atPath: logFilePath) {
                try FileManager.default.removeItem(atPath: logFilePath)
            }
            FileManager.default.createFile(atPath: logFilePath, contents: nil, attributes: nil)
            logText += "✅ Log file cleared.\n"
            
            // Reset isSetupComplete if setup files are deleted
            if !checkSetupFiles() {
                self.isSetupComplete = false
                UserDefaults.standard.set(false, forKey: "isSetupComplete")
            }
        } catch {
            logText += "❌ ERROR: Failed to clear log file - \(error.localizedDescription)\n"
        }
    
    }
    
    // Monitor Logs
    func monitorLogs() {
        let logFilePath = FileManager.default.homeDirectoryForCurrentUser.path + "/timeleap/timeleap.log"
        
        DispatchQueue.global(qos: .background).async {
            while true {
                if FileManager.default.fileExists(atPath: logFilePath) {
                    if let logs = try? String(contentsOfFile: logFilePath, encoding: .utf8) {
                        DispatchQueue.main.async {
                            self.monitoringText = logs
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        self.monitoringText = "⚠️ No logs found. Is Timeleap running?"
                    }
                }
                Thread.sleep(forTimeInterval: 2)
            }
        }
    }
    
    func checkSetupFiles() -> Bool {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path
        let timeleapDir = "\(homeDirectory)/timeleap"
        let confYamlPath = "\(timeleapDir)/conf.yaml"
        let secretsYamlPath = "\(timeleapDir)/secrets.yaml"
        
        // Check if both conf.yaml and secrets.yaml exist
        return FileManager.default.fileExists(atPath: confYamlPath) && FileManager.default.fileExists(atPath: secretsYamlPath)
    }
    
    func setupTimeleap() {
        logText += "Starting setup...\n"
        statusText = "Status: Setting up...\n"
        
        DispatchQueue.global().async {
            self.checkAndInstallDependencies()
            
            let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path
            let timeleapDir = "\(homeDirectory)/timeleap"
            let confYamlPath = "\(timeleapDir)/conf.yaml"
            let secretsYamlPath = "\(timeleapDir)/secrets.yaml"
            let logFilePath = "\(timeleapDir)/timeleap.log"
            let timeleapPath = "\(homeDirectory)/.local/bin/timeleap"
            
            if !FileManager.default.fileExists(atPath: timeleapPath) {
                DispatchQueue.main.async {
                    self.logText += "⚠️ Timeleap CLI not found. Please download it first.\n"
                }
                return
            }
            
            self.runShellCommand("mkdir -p \(timeleapDir)")
            self.runShellCommand("touch \(logFilePath)")
            self.runShellCommand("rm -rf \(timeleapDir) && mkdir -p \(timeleapDir)")
            self.runShellCommand("chmod -R 755 \(timeleapDir)") // Set permissions
            
            if !FileManager.default.fileExists(atPath: timeleapDir) {
                DispatchQueue.main.async {
                    self.logText += "Error: Failed to download Timeleap CLI.\n"
                }
                return
            }
            
            self.runShellCommand("file \(timeleapDir)")
            self.runShellCommand("ls -l \(timeleapDir)")
            self.runShellCommand("file \(timeleapDir)")
            self.runShellCommand("chmod +x \(timeleapPath)")
            
            let initialConfYaml = """
            system:
              log: info
              name: Timeleap
            
            network:
              bind: 0.0.0.0:9123
              broker:
                uri: ws://localhost:9123
                publicKey: "publicKey"
            
            rpc:
              cpus: 1
              gpus: 0
              ram: 1024
            
            pos:
              rpc:
                - https://arbitrum.llamarpc.com
            """
            
            do {
                try initialConfYaml.write(toFile: confYamlPath, atomically: true, encoding: .utf8)
                DispatchQueue.main.async {
                    self.logText += "✅ Initial conf.yaml written successfully!\n"
                }
            } catch {
                DispatchQueue.main.async {
                    self.logText += "❌ ERROR: Could not write initial conf.yaml\n"
                }
                return
            }
            
            // Check if secrets.yaml already exists
            if FileManager.default.fileExists(atPath: secretsYamlPath) {
                DispatchQueue.main.async {
                    self.logText += "🔑 Found existing secrets.yaml. Using existing public key.\n"
                }
                
                // Read the publicKey from the existing secrets.yaml
                if let secretsYamlContents = try? String(contentsOfFile: secretsYamlPath, encoding: .utf8) {
                    let lines = secretsYamlContents.components(separatedBy: .newlines)
                    for line in lines {
                        if line.contains("publicKey:") {
                            let publicKey = line.components(separatedBy: " ")[1]
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                .replacingOccurrences(of: "\"", with: "") // Remove quotation marks
                            
                            // Update the publicKey state variable
                            DispatchQueue.main.async {
                                self.publicKey = publicKey
                            }
                            
                            // Update conf.yaml with the existing publicKey
                            do {
                                var confYamlContents = try String(contentsOfFile: confYamlPath, encoding: .utf8)
                                confYamlContents = confYamlContents.replacingOccurrences(
                                    of: "publicKey: \"publicKey\"",
                                    with: "publicKey: \(publicKey)" // No quotation marks here
                                )
                                try confYamlContents.write(toFile: confYamlPath, atomically: true, encoding: .utf8)
                                DispatchQueue.main.async {
                                    self.logText += "✅ Updated conf.yaml with existing public key: \(publicKey)\n"
                                }
                            } catch {
                                DispatchQueue.main.async {
                                    self.logText += "❌ ERROR: Could not update conf.yaml with public key\n"
                                }
                            }
                            break
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        self.logText += "❌ ERROR: Could not read existing secrets.yaml\n"
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.logText += "🔑 Generating new secrets.yaml...\n"
                }
                
                // Check for port conflicts
                let portCheckCommand = "lsof -i :9123"
                let portCheckOutput = self.runShellCommandAndReturnOutput(portCheckCommand)
                DispatchQueue.main.async {
                    self.logText += "Port check output: \(portCheckOutput)\n"
                }
                
                if !portCheckOutput.isEmpty {
                    self.runShellCommand("kill -9 $(lsof -t -i :9123)")
                    DispatchQueue.main.async {
                        self.logText += "Terminated processes using port 9123.\n"
                    }
                }
                
                // Terminate any existing broker process
                DispatchQueue.global().asyncAfter(deadline: .now() + 1) { // Wait 5 seconds
                    self.runShellCommand("pkill -f 'timeleap broker'")
                }
                
                // Run the broker process to generate secrets
                self.runShellCommand("cd \(timeleapDir) && \(timeleapPath) broker --allow-generate-secrets")
                
                // Terminate the broker process after generating secrets
                self.runShellCommand("pkill -f 'timeleap broker'")
                
                // Check if secrets.yaml was generated
                if !FileManager.default.fileExists(atPath: secretsYamlPath) {
                    DispatchQueue.main.async {
                        self.logText += "❌ ERROR: secrets.yaml was not generated. Check if the Timeleap binary is working.\n"
                    }
                }
                
                // Read and update conf.yaml with the public key from secrets.yaml
                if let secretsYamlContents = try? String(contentsOfFile: secretsYamlPath, encoding: .utf8) {
                    let lines = secretsYamlContents.components(separatedBy: .newlines)
                    for line in lines {
                        if line.contains("publicKey:") {
                            let publicKey = line.components(separatedBy: " ")[1]
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                .replacingOccurrences(of: "\"", with: "") // Remove quotation marks
                            
                            // Update the publicKey state variable
                            DispatchQueue.main.async {
                                self.publicKey = publicKey
                            }
                            
                            // Update conf.yaml with the new publicKey
                            do {
                                var confYamlContents = try String(contentsOfFile: confYamlPath, encoding: .utf8)
                                confYamlContents = confYamlContents.replacingOccurrences(
                                    of: "publicKey: \"publicKey\"",
                                    with: "publicKey: \(publicKey)" // No quotation marks here
                                )
                                try confYamlContents.write(toFile: confYamlPath, atomically: true, encoding: .utf8)
                                DispatchQueue.main.async {
                                    self.logText += "✅ Updated conf.yaml with new public key: \(publicKey)\n"
                                }
                            } catch {
                                DispatchQueue.main.async {
                                    self.logText += "❌ ERROR: Could not update conf.yaml with public key\n"
                                }
                            }
                            break
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        self.logText += "❌ ERROR: Could not read secrets.yaml\n"
                    }
                }
            }
            
            DispatchQueue.main.async {
                self.logText += "Setup complete!\n"
                self.statusText = "Status: Ready!\n"
                self.isSetupComplete = true
                
                // Save the setup completion state to UserDefaults
                UserDefaults.standard.set(true, forKey: "isSetupComplete")
            }
        }
    }
    
    func runShellCommand(_ command: String) {
        let task = Process()
        let pipe = Pipe()
        let errorPipe = Pipe()

        task.standardOutput = pipe
        task.standardError = errorPipe
        task.arguments = ["-c", command]
        task.executableURL = URL(fileURLWithPath: "/bin/bash")

        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let errorOutput = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            DispatchQueue.main.async {
                self.logText += "Executing: \(command)\n"
                
                // Append output only if it's not empty
                if !output.isEmpty {
                    self.logText += "Output: \(output)\n"
                }
                
                // Append error only if it's not empty
                if !errorOutput.isEmpty {
                    self.logText += "Error: \(errorOutput)\n"
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.logText += "Error: \(error.localizedDescription)\n"
            }
        }
    }
    
    func runShellCommandAndReturnOutput(_ command: String) -> String {
        let task = Process()
        let pipe = Pipe()
        
        task.standardOutput = pipe
        task.arguments = ["-c", command]
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        
        var output = ""
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            output = String(data: data, encoding: .utf8) ?? ""
        } catch {
            DispatchQueue.main.async {
                self.logText += "Error executing: \(command)\n"
            }
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    func checkPermissions(at path: String) -> Bool {
        return FileManager.default.isWritableFile(atPath: path)
    }
    
    func checkAndInstallDependencies() {
        if !commandExists("/opt/homebrew/bin/brew") {
            logText += "Homebrew not found. Installing Homebrew...\n"
            runShellCommand("""
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            """)
        } else {
            logText += "Homebrew is already installed.\n"
        }
        
        if !commandExists("/opt/homebrew/bin/node") {
            logText += "Node.js not found. Installing Node.js...\n"
            runShellCommand("/opt/homebrew/bin/brew install node")
            runShellCommand("export PATH=/opt/homebrew/bin:$PATH")
        } else {
            logText += "Node.js is already installed.\n"
        }
        
        runShellCommand("/opt/homebrew/bin/node -v")
        
        if !commandExists("/opt/homebrew/bin/yarn") {
            logText += "Yarn not found. Installing Yarn...\n"
            runShellCommand("/opt/homebrew/bin/brew install yarn")
        } else {
            logText += "Yarn is already installed.\n"
        }
        
        if !commandExists("curl") {
            logText += "curl not found. Please install curl manually.\n"
        } else {
            logText += "curl is already installed.\n"
        }
    }
    
    func commandExists(_ command: String) -> Bool {
        let task = Process()
        let pipe = Pipe()
        
        task.standardOutput = pipe
        task.standardError = pipe
        task.arguments = ["-c", "which \(command)"]
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return !output.isEmpty
        } catch {
            return false
        }
    }
    func updateConfYaml() {
          let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path
          let timeleapDir = "\(homeDirectory)/timeleap"
          let confYamlPath = "\(timeleapDir)/conf.yaml"
          
          let confYamlContent = """
          system:
            log: \(logLevel)
            name: \(systemName)
          
          network:
            bind: \(bindAddress)
            broker:
              uri: \(brokerURI)
              publicKey: "\(publicKey)"
          
          rpc:
            cpus: \(cpus)
            gpus: \(gpus)
            ram: \(ram)
          
          pos:
            rpc:
              - \(rpc)
          """
          
          do {
              try confYamlContent.write(toFile: confYamlPath, atomically: true, encoding: .utf8)
              logText += "✅ conf.yaml updated successfully!\n"
          } catch {
              logText += "❌ ERROR: Could not update conf.yaml\n"
          }
      }
    func loadConfYaml() {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path
        let timeleapDir = "\(homeDirectory)/timeleap"
        let confYamlPath = "\(timeleapDir)/conf.yaml"
        
        guard FileManager.default.fileExists(atPath: confYamlPath) else {
            logText += "⚠️ conf.yaml not found at \(confYamlPath). Using default values.\n"
            return
        }
        
        do {
            let confYamlContents = try String(contentsOfFile: confYamlPath, encoding: .utf8)
            let lines = confYamlContents.components(separatedBy: .newlines)
            
            var isPosSection = false
            
            for line in lines {
                // Debug: Print the current line being parsed
                print("Parsing line: \(line)")
                
                if line.contains("pos:") {
                    isPosSection = true
                    print("Entered pos section. isPosSection: \(isPosSection)")
                } else if isPosSection && line.contains("rpc:") {
                    // Debug: Print when the rpc field is found
                    print("Found rpc field in pos section.")
                    
                    // Extract the RPC value
                    let rpcLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if rpcLine.contains("-") {
                        let rpcValue = rpcLine.components(separatedBy: "-")[1]
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        DispatchQueue.main.async {
                            self.rpc = rpcValue
                        }
                        print("Extracted RPC value: \(rpcValue)")
                    }
                } else if line.contains(":") && !line.contains("rpc:") {
                    isPosSection = false // Exit the pos section
                    print("Exited pos section. isPosSection: \(isPosSection)")
                }
                
                // Parse other fields (existing logic)
                if line.contains("log:") {
                    logLevel = line.components(separatedBy: " ").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? logLevel
                    print("Extracted logLevel: \(logLevel)")
                } else if line.contains("name:") {
                    systemName = line.components(separatedBy: " ").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? systemName
                    print("Extracted systemName: \(systemName)")
                } else if line.contains("bind:") {
                    bindAddress = line.components(separatedBy: " ").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? bindAddress
                    print("Extracted bindAddress: \(bindAddress)")
                } else if line.contains("uri:") {
                    brokerURI = line.components(separatedBy: " ").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? brokerURI
                    print("Extracted brokerURI: \(brokerURI)")
                } else if line.contains("publicKey:") {
                    publicKey = line.components(separatedBy: " ").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? publicKey
                    print("Extracted publicKey: \(publicKey)")
                } else if line.contains("cpus:") {
                    cpus = line.components(separatedBy: " ").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? cpus
                    print("Extracted cpus: \(cpus)")
                } else if line.contains("gpus:") {
                    gpus = line.components(separatedBy: " ").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? gpus
                    print("Extracted gpus: \(gpus)")
                } else if line.contains("ram:") {
                    ram = line.components(separatedBy: " ").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ram
                    print("Extracted ram: \(ram)")
                }
            }
            
            logText += "✅ conf.yaml loaded successfully!\n"
        } catch {
            logText += "❌ ERROR: Could not read conf.yaml - \(error.localizedDescription)\n"
        }
    }
} // Close the ContentView struct

// Configuration View
struct ConfigurationView: View {
    @Binding var logLevel: String
    @Binding var systemName: String
    @Binding var bindAddress: String
    @Binding var brokerURI: String
    @Binding var publicKey: String
    @Binding var cpus: String
    @Binding var gpus: String
    @Binding var ram: String
    @Binding var rpc: String
    
    var updateConfYaml: () -> Void
    var closeConfiguration: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Configuration").font(.headline)
            
            // Log Level
            HStack {
                Text("Log Level:")
                    .frame(width: 100, alignment: .leading)
                    .help("Set the logging level (e.g., info, debug, warn).") // Tooltip
                Spacer()
                TextField("Log Level", text: $logLevel)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 200)
            }
            
            // System Name
            HStack {
                Text("System Name:")
                    .frame(width: 100, alignment: .leading)
                    .help("The name of the system or node.") // Tooltip
                Spacer()
                TextField("System Name", text: $systemName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 200)
            }
            
            // Bind Address
            HStack {
                Text("Bind Address:")
                    .frame(width: 100, alignment: .leading)
                    .help("The address and port to bind the node to (e.g., 0.0.0.0:9123).") // Tooltip
                Spacer()
                TextField("Bind Address", text: $bindAddress)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 200)
            }
            
            // Broker URI
            HStack {
                Text("Broker URI:")
                    .frame(width: 100, alignment: .leading)
                    .help("The URI of the broker node (e.g., ws://localhost:9123).") // Tooltip
                Spacer()
                TextField("Broker URI", text: $brokerURI)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 200)
            }
            
            // Public Key
            HStack {
                Text("Public Key:")
                    .frame(width: 100, alignment: .leading)
                    .help("The public key for the node, used for secure communication.") // Tooltip
                Spacer()
                TextField("Public Key", text: $publicKey)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 200)
            }
            
            // CPUs
            HStack {
                Text("CPUs:")
                    .frame(width: 100, alignment: .leading)
                    .help("The number of CPU cores allocated to the node.") // Tooltip
                Spacer()
                TextField("CPUs", text: $cpus)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 200)
            }
            
            // GPUs
            HStack {
                Text("GPUs:")
                    .frame(width: 100, alignment: .leading)
                    .help("The number of GPU cores allocated to the node.") // Tooltip
                Spacer()
                TextField("GPUs", text: $gpus)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 200)
            }
            
            // RAM
            HStack {
                Text("RAM (MB):")
                    .frame(width: 100, alignment: .leading)
                    .help("The amount of RAM (in MB) allocated to the node.") // Tooltip
                Spacer()
                TextField("RAM", text: $ram)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 200)
            }
            
            // RPC
            HStack {
                Text("RPC:")
                    .frame(width: 100, alignment: .leading)

                Spacer()
                TextField("RPC", text: $rpc)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 200)
            }
            
            // Buttons
            HStack {
                Button(action: { updateConfYaml() }) {
                    Text("Update Configuration")
                        .font(.headline)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                
                Button(action: { closeConfiguration() }) {
                    Text("Close")
                        .font(.headline)
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .padding()
    }
}

// Preview provider struct
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

extension ProcessInfo {
    var machineHardwareName: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }
}
