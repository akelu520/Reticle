/// Undo/redo over document snapshots. Annotation data is tiny, so snapshots are
/// simpler and safer than inverse operations.
public struct History<State> {
    public let limit: Int
    private var undoStack: [State] = []
    private var redoStack: [State] = []

    public init(limit: Int = 100) {
        self.limit = limit
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    /// Call with the state *before* a change.
    public mutating func record(_ state: State) {
        undoStack.append(state)
        if undoStack.count > limit { undoStack.removeFirst(undoStack.count - limit) }
        redoStack.removeAll()
    }

    /// Returns the state to restore, given the current one.
    public mutating func undo(from current: State) -> State? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        return previous
    }

    public mutating func redo(from current: State) -> State? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        return next
    }
}
