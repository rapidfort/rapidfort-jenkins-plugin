package io.jenkins.plugins.rapidfort;

import hudson.Extension;
import hudson.FilePath;
import hudson.Launcher;
import hudson.model.Run;
import hudson.model.TaskListener;
import hudson.tasks.BuildStepDescriptor;
import hudson.tasks.BuildStepMonitor;
import hudson.tasks.Builder;
import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import jenkins.tasks.SimpleBuildStep;
import org.jenkinsci.Symbol;
import org.kohsuke.stapler.DataBoundConstructor;

public class RapidFortInstallerBuilder extends Builder implements SimpleBuildStep {

    @DataBoundConstructor
    public RapidFortInstallerBuilder() {
        // constructor for the builder
    }

    @Override
    public void perform(Run<?, ?> run, FilePath workspace, Launcher launcher, TaskListener listener)
            throws InterruptedException, IOException {
        listener.getLogger().println("Starting Rapidfort installation...");

        try {
            RapidFortToolset toolset = new RapidFortToolset(listener);

            // Install the CLI using the extracted script
            toolset.installRapidFortCLI(workspace);

            // Test login
            RapidFortLogin(listener);

        } catch (Exception e) {
            listener.getLogger().println("Exception occurred: " + e.getMessage());
            throw new IOException("Installation failed.", e);
        }
    }

    private void RapidFortLogin(TaskListener listener) throws IOException, InterruptedException {
        listener.getLogger().println("Logging into RapidFort...");

        String rfAccessId = System.getenv("RF_ACCESS_ID");
        String rfAccessPassword = System.getenv("RF_ACCESS_PASSWORD");

        if (rfAccessId == null || rfAccessPassword == null) {
            throw new IOException("Environment variables RF_ACCESS_ID or RF_ACCESS_PASSWORD are not set.");
        }

        String command = "rflogin \"" + rfAccessId + "\" \"" + rfAccessPassword + "\"";

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
            throw new IOException("rflogin failed. Stopping the build.");
        }
    }

    @Override
    public BuildStepMonitor getRequiredMonitorService() {
        return BuildStepMonitor.NONE;
    }

    @Extension
    @Symbol("rapidfortInstaller")
    public static final class DescriptorImpl extends BuildStepDescriptor<Builder> {
        @Override
        public boolean isApplicable(Class<? extends hudson.model.AbstractProject> jobType) {
            return true;
        }

        @Override
        public String getDisplayName() {
            return "Rapidfort Installer";
        }
    }
}
