/// Checked advancement for session-local issuers. Failure preserves the last value;
/// the owner must stop issuing work rather than reset or reuse the identifier.
public enum LifecycleCounter {
  @discardableResult
  public static func advance<Value: FixedWidthInteger>(_ value: inout Value) -> Bool {
    let (next, overflow) = value.addingReportingOverflow(1)
    guard !overflow else { return false }
    value = next
    return true
  }
}
