module.exports = {
  branches: ["main", { name: "develop", prerelease: "develop" }],
  tagFormat: "v${version}",
  plugins: [
    [
      "@semantic-release/commit-analyzer",
      {
        preset: "conventionalcommits",
      },
    ],
    [
      "@semantic-release/release-notes-generator",
      {
        preset: "conventionalcommits",
      },
    ],
    [
      "@semantic-release/npm",
      {
        npmPublish: false,
      },
    ],
    [
      "@semantic-release/git",
      {
        assets: ["package.json", "package-lock.json"],
        // IMPORTANT: never use the GitHub-native "[skip ci]" / "[ci skip]" /
        // "[no ci]" / "[skip actions]" / "[actions skip]" markers here.
        // GitHub silently drops EVERY workflow run (push AND pull_request)
        // tied to a commit whose message matches one of those patterns —
        // including PR checks for any PR whose head lands on this commit.
        // Use a custom marker instead; only this repo's own release workflow
        // guard needs to recognize it.
        message:
          "chore(release): ${nextRelease.version} [release-sync]\n\n${nextRelease.notes}",
      },
    ],
    "@semantic-release/github",
    [
      "@semantic-release/exec",
      {
        publishCmd:
          "echo RELEASE_VERSION=${nextRelease.version} >> $GITHUB_ENV\n" +
          "echo RELEASE_GIT_TAG=${nextRelease.gitTag} >> $GITHUB_ENV",
      },
    ],
  ],
};
