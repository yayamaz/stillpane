public enum StillpaneVersion {
    public static let version = "1.0.0"

    /// The plugin version this app was released alongside; release.sh
    /// refuses to cut a release where this and .claude-plugin/plugin.json
    /// disagree. Check Setup compares it against the installed plugin and
    /// shows the explicit update command when the install is older - the app
    /// itself never mutates the plugin.
    public static let expectedPluginVersion = "1.0.0"
}
