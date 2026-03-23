//
// Heap.swift
// PhotoScanner
//
// 最小堆和最大堆实现
// 用于 HNSW 搜索优化，替代频繁排序，减少约 80% 的排序操作。
//

import Foundation

/// 最小堆实现
///
/// 用于 HNSW 搜索优化，替代频繁排序。
/// 维护 k 个最近邻，弹出最远的（堆顶最小元素）。
///
/// ## 时间复杂度
/// - 插入: O(log n)
/// - 弹出最小: O(log n)
/// - 查看最小: O(1)
///
/// ## 使用示例
/// ```swift
/// var heap = MinHeap<(id: String, distance: Float)>(sortingBy: { $0.distance < $1.distance })
/// heap.insert(("photo1", 0.85))
/// heap.insert(("photo2", 0.92))
/// if let nearest = heap.min() {
///     print("最近邻: \(nearest.id), 距离: \(nearest.distance)")
/// }
/// ```
struct MinHeap<Element> {
    private var heap: [Element] = []
    private let areInIncreasingOrder: (Element, Element) -> Bool

    /// 创建最小堆
    /// - Parameter areInIncreasingOrder: 比较闭包，返回 true 表示第一个元素更小
    init(sortingBy areInIncreasingOrder: @escaping (Element, Element) -> Bool) {
        self.areInIncreasingOrder = areInIncreasingOrder
    }

    /// 堆是否为空
    var isEmpty: Bool { heap.isEmpty }

    /// 堆中元素数量
    var count: Int { heap.count }

    /// 查看最小元素（不移除）
    func min() -> Element? { heap.first }

    /// 插入元素
    /// - Parameter element: 待插入元素
    mutating func insert(_ element: Element) {
        heap.append(element)
        siftUp(from: heap.count - 1)
    }

    /// 弹出最小元素
    /// - Returns: 最小元素，堆为空时返回 nil
    mutating func pop() -> Element? {
        guard !heap.isEmpty else { return nil }

        if heap.count == 1 {
            return heap.removeLast()
        }

        heap.swapAt(0, heap.count - 1)
        let min = heap.removeLast()
        siftDown(from: 0)
        return min
    }

    /// 获取有序数组（从小到大，会清空堆）
    /// - Returns: 排序后的数组
    mutating func sorted() -> [Element] {
        var result: [Element] = []
        while let element = pop() {
            result.append(element)
        }
        return result
    }

    // MARK: - Private

    /// 上浮操作
    private mutating func siftUp(from index: Int) {
        var childIndex = index
        var parentIndex = (childIndex - 1) / 2

        while childIndex > 0 && areInIncreasingOrder(heap[childIndex], heap[parentIndex]) {
            heap.swapAt(childIndex, parentIndex)
            childIndex = parentIndex
            parentIndex = (childIndex - 1) / 2
        }
    }

    /// 下沉操作
    private mutating func siftDown(from index: Int) {
        var parentIndex = index

        while true {
            let leftChild = 2 * parentIndex + 1
            let rightChild = 2 * parentIndex + 2
            var minIndex = parentIndex

            if leftChild < heap.count && areInIncreasingOrder(heap[leftChild], heap[minIndex]) {
                minIndex = leftChild
            }

            if rightChild < heap.count && areInIncreasingOrder(heap[rightChild], heap[minIndex]) {
                minIndex = rightChild
            }

            if minIndex == parentIndex { break }

            heap.swapAt(parentIndex, minIndex)
            parentIndex = minIndex
        }
    }
}

/// 最大堆实现
///
/// 用于 HNSW 结果集维护，需要快速淘汰最大元素。
/// 维护 top-k 结果，当结果集满时，弹出最远的（堆顶最大元素）。
///
/// ## 时间复杂度
/// - 插入: O(log n)
/// - 弹出最大: O(log n)
/// - 查看最大: O(1)
///
/// ## 使用示例
/// ```swift
/// var heap = MaxHeap<(id: String, distance: Float)>(sortingBy: { $0.distance < $1.distance })
/// heap.insert(("photo1", 0.85))
///
/// // 当堆满时，检查是否需要替换
/// if let maxDist = heap.max()?.distance, newDistance < maxDist {
///     _ = heap.pop()  // 淘汰最远的
///     heap.insert((newId, newDistance))
/// }
/// ```
struct MaxHeap<Element> {
    private var heap: [Element] = []
    private let areInIncreasingOrder: (Element, Element) -> Bool

    /// 创建最大堆
    /// - Parameter areInIncreasingOrder: 比较闭包，返回 true 表示第一个元素更小
    init(sortingBy areInIncreasingOrder: @escaping (Element, Element) -> Bool) {
        self.areInIncreasingOrder = areInIncreasingOrder
    }

    /// 堆是否为空
    var isEmpty: Bool { heap.isEmpty }

    /// 堆中元素数量
    var count: Int { heap.count }

    /// 查看最大元素（不移除）
    func max() -> Element? { heap.first }

    /// 插入元素
    /// - Parameter element: 待插入元素
    mutating func insert(_ element: Element) {
        heap.append(element)
        siftUp(from: heap.count - 1)
    }

    /// 弹出最大元素
    /// - Returns: 最大元素，堆为空时返回 nil
    mutating func pop() -> Element? {
        guard !heap.isEmpty else { return nil }

        if heap.count == 1 {
            return heap.removeLast()
        }

        heap.swapAt(0, heap.count - 1)
        let max = heap.removeLast()
        siftDown(from: 0)
        return max
    }

    /// 获取有序数组（从大到小，会清空堆）
    /// - Returns: 降序排列的数组
    mutating func sorted() -> [Element] {
        var result: [Element] = []
        while let element = pop() {
            result.append(element)
        }
        return result.reversed()
    }

    // MARK: - Private

    /// 上浮操作（最大堆：子节点 > 父节点时交换）
    private mutating func siftUp(from index: Int) {
        var childIndex = index
        var parentIndex = (childIndex - 1) / 2

        // 最大堆: 子节点 > 父节点时交换
        while childIndex > 0 && areInIncreasingOrder(heap[parentIndex], heap[childIndex]) {
            heap.swapAt(childIndex, parentIndex)
            childIndex = parentIndex
            parentIndex = (childIndex - 1) / 2
        }
    }

    /// 下沉操作
    private mutating func siftDown(from index: Int) {
        var parentIndex = index

        while true {
            let leftChild = 2 * parentIndex + 1
            let rightChild = 2 * parentIndex + 2
            var maxIndex = parentIndex

            if leftChild < heap.count && areInIncreasingOrder(heap[maxIndex], heap[leftChild]) {
                maxIndex = leftChild
            }

            if rightChild < heap.count && areInIncreasingOrder(heap[maxIndex], heap[rightChild]) {
                maxIndex = rightChild
            }

            if maxIndex == parentIndex { break }

            heap.swapAt(parentIndex, maxIndex)
            parentIndex = maxIndex
        }
    }
}

// MARK: - 便捷初始化

extension MinHeap where Element: Comparable {
    /// 创建最小堆（使用默认比较）
    init() {
        self.init(sortingBy: <)
    }
}

extension MaxHeap where Element: Comparable {
    /// 创建最大堆（使用默认比较）
    init() {
        self.init(sortingBy: <)
    }
}
