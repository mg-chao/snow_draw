#![allow(dead_code)]

/// A generic min-heap that orders elements by a caller-supplied score.
///
/// Used by the elbow A* grid router and reusable by other subsystems that
/// need priority-queue behavior.
pub struct BinaryHeap<T, F>
where
    F: Fn(&T) -> f64,
{
    score: F,
    content: Vec<T>,
}

impl<T, F> BinaryHeap<T, F>
where
    F: Fn(&T) -> f64,
{
    /// Creates a heap that orders elements by the given scoring function
    /// (lowest first).
    pub fn new(score: F) -> Self {
        Self {
            score,
            content: Vec::new(),
        }
    }

    /// Whether the heap contains no elements.
    pub fn is_empty(&self) -> bool {
        self.content.is_empty()
    }

    /// Whether the heap contains at least one element.
    pub fn is_not_empty(&self) -> bool {
        !self.content.is_empty()
    }

    /// Adds `element` to the heap.
    pub fn push(&mut self, element: T) {
        self.content.push(element);
        let last_index = self.content.len() - 1;
        self.sink_down(last_index);
    }

    /// Removes and returns the element with the lowest score.
    ///
    /// Returns `None` if the heap is empty.
    pub fn pop(&mut self) -> Option<T> {
        if self.content.is_empty() {
            return None;
        }

        let result = self.content.swap_remove(0);
        if !self.content.is_empty() {
            self.bubble_up(0);
        }
        Some(result)
    }

    fn score_at(&self, index: usize) -> f64 {
        (self.score)(&self.content[index])
    }

    fn sink_down(&mut self, mut index: usize) {
        while index > 0 {
            let parent_index = ((index + 1) >> 1) - 1;
            if self.score_at(index) < self.score_at(parent_index) {
                self.content.swap(index, parent_index);
                index = parent_index;
            } else {
                break;
            }
        }
    }

    fn bubble_up(&mut self, mut index: usize) {
        let length = self.content.len();
        loop {
            let child2_index = (index + 1) << 1;
            let child1_index = child2_index - 1;
            let mut swap_index: Option<usize> = None;

            if child1_index < length && self.score_at(child1_index) < self.score_at(index) {
                swap_index = Some(child1_index);
            }

            if child2_index < length {
                let compare_index = swap_index.unwrap_or(index);
                if self.score_at(child2_index) < self.score_at(compare_index) {
                    swap_index = Some(child2_index);
                }
            }

            if let Some(next_index) = swap_index {
                self.content.swap(index, next_index);
                index = next_index;
            } else {
                break;
            }
        }
    }
}

impl<T, F> BinaryHeap<T, F>
where
    T: PartialEq,
    F: Fn(&T) -> f64,
{
    /// Whether the heap contains `element`.
    pub fn contains(&self, element: &T) -> bool {
        self.content.contains(element)
    }

    /// Re-positions `element` after its score has changed.
    ///
    /// If `element` is not in the heap this is a no-op.
    pub fn rescore(&mut self, element: &T) {
        if let Some(index) = self.content.iter().position(|item| item == element) {
            self.sink_down(index);
        }
    }
}
