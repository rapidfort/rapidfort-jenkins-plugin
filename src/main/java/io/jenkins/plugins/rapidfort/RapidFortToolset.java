package io.jenkins.plugins.rapidfort;

import hudson.FilePath;
import hudson.model.TaskListener;
import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;

public class RapidFortToolset {

    private final TaskListener listener;

    public RapidFortToolset(TaskListener listener) {
        this.listener = listener;
    }

    /**
     * Onboards `rf_installer.sh` script to the Jenkins workspace.
     *
     * @param workspace The Jenkins workspace where the script should be copied
     * @return FilePath of the script in the workspace
     * @throws IOException if the file cannot be copied
     * @throws InterruptedException if the process is interrupted
     */
    public FilePath onboardInstallerToWorkspace(FilePath workspace) throws IOException, InterruptedException {
        listener.getLogger().println("Extracting rf_installer.sh from HPI to the workspace...");

        FilePath targetFile = workspace.child("rf_installer.sh");

        try (InputStream inputStream =
                getClass().getClassLoader().getResourceAsStream("io/jenkins/plugins/rapidfort/rf_installer.sh")) {
            if (inputStream == null) {
                throw new IOException("Unable to find rf_installer.sh in plugin resources.");
            }

            try (OutputStream outputStream = targetFile.write()) {
                byte[] buffer = new byte[1024];
                int length;
                while ((length = inputStream.read(buffer)) != -1) {
                    outputStream.write(buffer, 0, length);
                }
            }
        }

        listener.getLogger().println("Successfully extracted rf_installer.sh to " + targetFile.getRemote());
        return targetFile;
    }

    /**
     * Util for running shell command
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

        try (BufferedReader reader =
                new BufferedReader(new InputStreamReader(process.getInputStream(), StandardCharsets.UTF_8))) {
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
     * Install RapidFort CLI
     *
     * @param workspace The Jenkins workspace where the script is present
     * @throws IOException, InterruptedException if installation fails
     */
    public void installRapidFortCLI(FilePath workspace) throws IOException, InterruptedException {
        if (workspace == null) {
            throw new IllegalArgumentException("Workspace null.");
        }

        listener.getLogger().println("Installing Rapidfort CLI...");
        FilePath installerScript = onboardInstallerToWorkspace(workspace);
        String[] commands = {"chmod +x " + installerScript.getRemote(), installerScript.getRemote()};

        for (String command : commands) {
            listener.getLogger().println("Running command: " + command);
            if (!runCommand(command)) {
                throw new IOException("Command failed. Stopping the build.");
            }
        }

        listener.getLogger().println("Rapidfort CLI installation completed successfully.");
    }
}
