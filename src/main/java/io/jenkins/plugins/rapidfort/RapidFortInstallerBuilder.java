package io.jenkins.plugins.rapidfort;

import com.cloudbees.plugins.credentials.CredentialsProvider;
import com.cloudbees.plugins.credentials.common.StandardUsernamePasswordCredentials;
import hudson.Extension;
import hudson.FilePath;
import hudson.Launcher;
import hudson.model.Item;
import hudson.model.Run;
import hudson.model.TaskListener;
import hudson.tasks.BuildStepDescriptor;
import hudson.tasks.BuildStepMonitor;
import hudson.tasks.Builder;
import hudson.util.ListBoxModel;
import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.Collections;
import jenkins.tasks.SimpleBuildStep;
import org.jenkinsci.Symbol;
import org.kohsuke.stapler.AncestorInPath;
import org.kohsuke.stapler.DataBoundConstructor;
import org.kohsuke.stapler.DataBoundSetter;

public class RapidFortInstallerBuilder extends Builder implements SimpleBuildStep {

    private String credentialsId;

    @DataBoundConstructor
    public RapidFortInstallerBuilder() {
        // No-arg constructor for the builder
    }

    @DataBoundSetter
    public void setCredentialsId(String credentialsId) {
        this.credentialsId = credentialsId;
    }

    public String getCredentialsId() {
        return credentialsId;
    }

    @Override
    public void perform(Run<?, ?> run, FilePath workspace, Launcher launcher, TaskListener listener)
            throws InterruptedException, IOException {
        listener.getLogger().println("Starting Rapidfort installation...");

        try {
            // Validate credentials ID
            if (credentialsId == null || credentialsId.trim().isEmpty()) {
                throw new IOException("No credentials ID provided. Please select a valid credential.");
            }

            // Get credentials from Jenkins store
            StandardUsernamePasswordCredentials credentials = CredentialsProvider.findCredentialById(
                    credentialsId, StandardUsernamePasswordCredentials.class, run);

            if (credentials == null) {
                throw new IOException("Could not find credentials with ID: " + credentialsId);
            }

            String rfAccessId = credentials.getUsername();
            String rfAccessPassword = credentials.getPassword().getPlainText();

            RapidFortToolset toolset = new RapidFortToolset(listener);
            toolset.installRapidFortCLI(workspace);
            //AV: Skipping RF Login
            //RapidFortLogin(listener, rfAccessId, rfAccessPassword);

        } catch (Exception e) {
            listener.getLogger().println("Exception occurred: " + e.getMessage());
            throw new IOException("Installation failed.", e);
        }
    }
    // Rf login
    private void RapidFortLogin(TaskListener listener, String rfAccessId, String rfAccessPassword)
            throws IOException, InterruptedException {
        listener.getLogger().println("Logging into RapidFort...");

        if (rfAccessId == null || rfAccessPassword == null) {
            throw new IOException("Credentials for RF_ACCESS_ID or RF_ACCESS_PASSWORD are not set.");
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

        public ListBoxModel doFillCredentialsIdItems(@AncestorInPath Item context) {
            ListBoxModel items = new ListBoxModel();
            if (context == null || !context.hasPermission(Item.CONFIGURE)) {
                return items;
            }
            items.add("Select credentials", "");
            for (StandardUsernamePasswordCredentials c : CredentialsProvider.lookupCredentials(
                    StandardUsernamePasswordCredentials.class, context, null, Collections.emptyList())) {
                items.add(c.getDescription(), c.getId());
            }
            return items;
        }
    }
}
