# Kali Config
This repo contains my personal configuration for freshly installed Kali Linux to streamline my workflow.

# What Does It Do?
The setup.sh script performs the following tasks:
- Updates and upgrades all Kali Linux packages.
- Installs the XFCE4 Terminal and sets it as the default terminal.
- Enhances the ZSH prompt by adding a Date and Time feature, useful for logging during exams or engagements.
- Configures tmux with an autologging feature using the settings in `tmux.conf`.
- Changes ownership of the `/opt` directory to the current user, where I store all my tools.
- Installs the latest version of Golang and sets up the environment variables.
- Enables passwordless sudo for the user.

# To Do 

- Configuring Mozilla Firefox with pentesting addons such as FoxyProxy, OWASP ZAP, and more.
- Setting up various pentesting tools including BloodHound CE, Nuclei, GoSpider, Subfinder, and others.

