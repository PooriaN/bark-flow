# Verification status

The 0.6.2 source has not yet been published as an installer release.

- A real microphone-to-field dictation was confirmed by the user on locally installed 0.6.1.
- Plus and standard Bark both transcribed a synthetic audio clip using the local speech engine. Switching standard back to Plus passed in the same process. The standard model was downloaded and verified against pinned publisher hashes.
- Pro transcribed the synthetic clip in a fresh process. The subsequent Pro-to-Plus switch was interrupted when available disk space fell below 4 GiB, so that transition remains unverified.
- A separate 0.6.2 candidate transcribed the synthetic clip with Plus. The candidate disk image passed its checksum and signature checks; it includes Plus only.
- Cold preparation on the test Mac took roughly 9 minutes for Plus and 9 minutes for standard during switching, and more than 15 minutes for a separate 0.6.2 Plus run. Times vary with device and system load. No independent clean-Mac test was run.
- Builds are ad hoc signed and not notarized. The installer release remains 0.6.0 pending the remaining checks.
