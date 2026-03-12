# Ace-Pace TODO / Roadmap

Project-level ideas and future work. Do not treat these as committed implementation plans.

- [ ] **Let the user choose between the extended or normal versions** — Add an option (CLI flag, env var, or config) so users can select extended vs normal One-Pace releases when fetching, matching, or renaming.
- [ ] **Rename using episode reference with [one-pace-for-plex](https://github.com/SpykerNZ/one-pace-for-plex/)** — Use that project’s episode naming/metadata (e.g. `One Pace - S01E01 - Romance Dawn, the Dawn of an Adventure.mkv`) as the target format for the rename feature instead of or in addition to the current scheme.
- [ ] **Clean feature** — New “clean” command/feature that:
  - Scans episodes in the library.
  - Keeps only the **most recent** version of each episode.
  - Respects the **version chosen** (extended or normal) from the version-choice setting above.
  - Is intended to be run **after rename** (and possibly integrated into the rename flow or documented as a follow-up step).
- [ ] **Long-term goal: Complete web UI** — Provide a full web interface for Ace-Pace (configuration, missing report, rename, clean, etc.) instead of/in addition to CLI and Docker env vars.
