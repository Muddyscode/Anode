# Evaluation

How well the measurement model and the grading engine do, measured honestly: misses included,
targets set from the first measurement rather than guessed (PRD, "How it is judged").

## Method

The same harness (`model/anode_model/evaluate.py`) scores every test set:

| Metric | Meaning |
|---|---|
| IoU, Dice | Overlap between the model's rust outline and the labelled one |
| Area error (percentage points) | |predicted % rusted − labelled % rusted|, mean and median |
| Ri exact / within one step | Ri from each % using the grading engine's own cut-offs (`lib/grading/ri-cutoffs.json`) |
| Ri under-graded | Share of photos where the model's Ri is lower than the label's: the safety number for the measurement step |

Escalation recall and mechanism agreement need expert labels and come with the gold set.

## Stage 6a: public held-out test set

The test split is chosen by a hash of each file name (about 10%) and never trained on. Results
are pasted here from the training notebook's `evaluation-public.md`.

**Not yet run.** No model has been trained yet; training runs in Colab with a Roboflow account
(see `model/README.md`).

## Stage 6b: gold set

About 200 photos labelled by Michael with grade, mechanism and severity, never used for training.
Adds escalation recall (share of S3 and S4 cases the Copilot also escalates) and mechanism
agreement (Michael's mechanism in the Copilot's top three).

**Not yet run.** Waiting for the gold set.

## Targets

Set after the first gold-set run, per the PRD.
