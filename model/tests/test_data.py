import pytest

from anode_model.data import Dataset, attribution_markdown, check_licence, coco_masks, split_of


def ds(licence: str) -> Dataset:
    return Dataset("Corrosion", "https://universe.roboflow.com/x/y", licence, "x", "y", 1)


@pytest.mark.parametrize("licence", ["CC BY 4.0", "cc0 1.0", " Public Domain ", "MIT"])
def test_allowed_licences(licence):
    check_licence(ds(licence))


@pytest.mark.parametrize("licence", ["CC BY-NC 4.0", "CC BY-SA 4.0", "Private", "", "unknown"])
def test_refused_licences(licence):
    with pytest.raises(ValueError):
        check_licence(ds(licence))


def test_attribution_lists_each_dataset_and_refuses_bad_ones():
    md = attribution_markdown([ds("CC BY 4.0")])
    assert "| Corrosion (v1) | CC BY 4.0 | https://universe.roboflow.com/x/y |" in md
    with pytest.raises(ValueError):
        attribution_markdown([ds("CC BY-NC 4.0")])


COCO = {
    "images": [
        {"id": 1, "file_name": "a.jpg", "width": 10, "height": 8},
        {"id": 2, "file_name": "b.jpg", "width": 4, "height": 4},
    ],
    "categories": [{"id": 1, "name": "rust"}, {"id": 2, "name": "paint"}],
    "annotations": [
        {"id": 1, "image_id": 1, "category_id": 1, "segmentation": [[1, 1, 5, 1, 5, 5, 1, 5]]},
        {"id": 2, "image_id": 1, "category_id": 2, "segmentation": [[6, 6, 9, 6, 9, 7]]},
        {"id": 3, "image_id": 1, "category_id": 1, "segmentation": [[0, 0, 1, 1]]},
    ],
}


def test_coco_masks_fill_rust_polygons_only():
    masks = coco_masks(COCO, {"rust"})
    assert masks["a.jpg"].shape == (8, 10)
    assert masks["a.jpg"][3, 3] and not masks["a.jpg"][6, 7]
    assert not masks["b.jpg"].any()
    assert coco_masks(COCO)["a.jpg"][6, 7]


def test_coco_masks_refuse_rle():
    bad = {**COCO, "annotations": [{"id": 9, "image_id": 1, "category_id": 1, "segmentation": {"counts": "x", "size": [8, 10]}}]}
    with pytest.raises(ValueError):
        coco_masks(bad)


def test_splits_are_deterministic_and_roughly_proportional():
    names = [f"img_{i}.jpg" for i in range(2000)]
    splits = [split_of(n) for n in names]
    assert splits == [split_of(n) for n in names]
    assert 140 < splits.count("test") < 260 and 140 < splits.count("val") < 260
    with pytest.raises(ValueError):
        split_of("a", val=0.6, test=0.5)
