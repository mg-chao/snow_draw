#![allow(dead_code)]

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct BoundRelationEntry {
    pub id: String,
    pub entry_type: String,
}

pub fn are_bound_relation_entries_equal(
    left: Option<&[BoundRelationEntry]>,
    right: Option<&[BoundRelationEntry]>,
) -> bool {
    match (left, right) {
        (None, None) => true,
        (Some(left), Some(right)) if left.len() == right.len() => {
            left.iter().zip(right).all(|(a, b)| a == b)
        }
        _ => false,
    }
}

pub fn merge_bound_relation_entries(
    entries: Option<&[BoundRelationEntry]>,
    target_type: &str,
    target_ids: &[String],
) -> Option<Vec<BoundRelationEntry>> {
    let mut merged = entries
        .unwrap_or_default()
        .iter()
        .filter(|entry| entry.entry_type != target_type)
        .cloned()
        .collect::<Vec<_>>();
    merged.extend(target_ids.iter().cloned().map(|id| BoundRelationEntry {
        id,
        entry_type: target_type.to_string(),
    }));
    (!merged.is_empty()).then_some(merged)
}

pub fn merge_arrow_bound_relation_entries(
    entries: Option<&[BoundRelationEntry]>,
    bound_arrow_ids: &[String],
) -> Option<Vec<BoundRelationEntry>> {
    merge_bound_relation_entries(entries, "arrow", bound_arrow_ids)
}
