#![allow(dead_code)]

use crate::draw::elements::core::typed_element_render_task_encoder::ElementState;

use super::serial_number_data::SerialNumberData;

/// Returns the highest serial number found in `elements`.
///
/// Returns `None` when no serial-number elements are present.
pub fn resolve_max_serial_number<'a, I>(elements: I) -> Option<i64>
where
    I: IntoIterator<Item = &'a ElementState>,
{
    let mut max_number: Option<i64> = None;

    for element in elements {
        let Some(number) = serial_number_of(element) else {
            continue;
        };

        if max_number.map_or(true, |current| number > current) {
            max_number = Some(number);
        }
    }

    max_number
}

/// Returns the next serial-number value that should be assigned.
///
/// Returns `None` when no serial-number elements are present.
pub fn resolve_next_serial_number<'a, I>(elements: I) -> Option<i64>
where
    I: IntoIterator<Item = &'a ElementState>,
{
    resolve_max_serial_number(elements).map(|max_number| max_number + 1)
}

fn serial_number_of(element: &ElementState) -> Option<i64> {
    element
        .data
        .as_ref()
        .as_any()
        .downcast_ref::<SerialNumberData>()
        .map(|data| data.number)
}
