import ast
import json
from pathlib import Path

NOTEBOOK = Path(__file__).resolve().parents[1] / "notebooks" / "train_unet.ipynb"


def test_notebook_code_cells_are_valid_python():
    nb = json.loads(NOTEBOOK.read_text())
    code = ["".join(c["source"]) for c in nb["cells"] if c["cell_type"] == "code"]
    assert len(code) >= 5
    for src in code:
        ast.parse("\n".join(line for line in src.splitlines() if not line.lstrip().startswith("!")))


def test_notebook_uses_the_tested_helpers_and_licence_check():
    src = NOTEBOOK.read_text()
    for needed in ("check_licence", "coco_masks", "split_of", "load_pairs", "report_markdown", "UNetPredictor"):
        assert needed in src
