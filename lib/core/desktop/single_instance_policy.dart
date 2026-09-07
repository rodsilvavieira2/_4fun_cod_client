/// Pure policy for the single-instance guard (no plugins, unit-testable).
bool shouldEnforceSingleInstance({
  required bool isWeb,
  required bool isDebug,
  required bool isLinux,
  required bool isWindows,
}) {
  if (isWeb || isDebug) return false;
  return isLinux || isWindows;
}
