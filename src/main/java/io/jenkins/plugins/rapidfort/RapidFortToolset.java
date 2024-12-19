package io.jenkins.plugins.rapidfort;

import hudson.FilePath;
import hudson.model.TaskListener;
import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;

public class RapidFortToolset {

    private final TaskListener listener;

    public RapidFortToolset(TaskListener listener) {
        this.listener = listener;
    }

    /**
     * Dependency check for curl
     * 
     * @throws IOException if curl is not found
     */
    public void checkCurlDependency() throws IOException, InterruptedException {
        listener.getLogger().println("Checking for 'curl' command availability...");
        String command = "command -v curl > /dev/null 2>&1";
        if (!runCommand(command)) {
            throw new IOException("'curl' command not found. Please install 'curl' on the agent.");
        }
        listener.getLogger().println("'curl' is available on the system.");
    }
    /**
     * Pull `rf_installer.sh` script into workspace workspace.
     *
     * @param workspace The Jenkins workspace where the script will be saved
     * @return FilePath of the script in the workspace
     * @throws IOException if the file cannot be downloaded or saved
     * @throws InterruptedException if the process is interrupted
     */
    public FilePath downloadInstallerToWorkspace(FilePath workspace) throws IOException, InterruptedException {
        listener.getLogger().println("Downloading rf_installer.sh from URL to the workspace...");

        // Target location in the Jenkins workspace
        FilePath targetFile = workspace.child("rf_installer.sh");
        String urlString = "https://us01.rapidfort.com/cli/";

        HttpURLConnection connection = null;
        try (OutputStream outputStream = targetFile.write()) {
            URL url = new URL(urlString);
            connection = (HttpURLConnection) url.openConnection();
            connection.setRequestMethod("GET");
            connection.setConnectTimeout(10000);
            connection.setReadTimeout(10000);

            int responseCode = connection.getResponseCode();
            if (responseCode != 200) {
                throw new IOException("Failed to download rf_installer.sh. HTTP Response Code: " + responseCode);
            }

            try (InputStream inputStream = connection.getInputStream()) {
                byte[] buffer = new byte[1024];
                int bytesRead;
                while ((bytesRead = inputStream.read(buffer)) != -1) {
                    outputStream.write(buffer, 0, bytesRead);
                }
            }
        } catch (IOException e) {
            throw new IOException("Error occurred while downloading rf_installer.sh: " + e.getMessage(), e);
        } finally {
            if (connection != null) {
                connection.disconnect();
            }
        }

        listener.getLogger().println("Successfully downloaded rf_installer.sh to " + targetFile.getRemote());
        return targetFile;
    }

    /**
     * Utility method for running shell commands.
     *
     * @param command The command to run
     * @return true if the command succeeds, false otherwise
     * @throws IOException, InterruptedException if the command fails
     */
    public boolean runCommand(String command) throws IOException, InterruptedException {
        listener.getLogger().println("Running command: " + command);
        ProcessBuilder processBuilder = new ProcessBuilder("sh", "-c", command);
        processBuilder.redirectErrorStream(true);
        Process process = processBuilder.start();

        try (BufferedReader reader = new BufferedReader(new InputStreamReader(process.getInputStream(), StandardCharsets.UTF_8))) {
            String line;
            while ((line = reader.readLine()) != null) {
                listener.getLogger().println(line);
            }
        }

        int exitCode = process.waitFor();
        if (exitCode != 0) {
            listener.getLogger().println("Command failed with exit code " + exitCode);
            return false;
        }
        return true;
    }

    /**
     * Installs the RapidFort CLI by downloading the installer script from the URL and running it.
     *
     * @param workspace The Jenkins workspace where the script will be executed
     * @throws IOException, InterruptedException if the installation process fails
     */
    public void installRapidFortCLI(FilePath workspace) throws IOException, InterruptedException {
        if (workspace == null) {
            throw new IllegalArgumentException("Workspace is null.");
        }

        // Step 1: Check if curl is available
        checkCurlDependency();

        listener.getLogger().println("Installing RapidFort CLI...");

        // Step 2: Download installer script to Jenkins workspace
        FilePath installerScript = downloadInstallerToWorkspace(workspace);

        // Step 3: Run the installer script
        String[] commands = {
            "chmod +x " + installerScript.getRemote(),
            installerScript.getRemote(),
            "rm " + installerScript.getRemote()  // Remove the installer after execution
        };

        for (String command : commands) {
            if (!runCommand(command)) {
                throw new IOException("Command failed. Stopping the build.");
            }
        }

        listener.getLogger().println("RapidFort CLI installation completed successfully.");
    }
}
