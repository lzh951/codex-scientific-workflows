# Examples

This folder contains public, synthetic fixtures for testing the reusable workflow tools without exposing private research data.

## Origin Batch Plot Fixture

`origin_batch_plot_sample.csv` is a small synthetic dataset with one X column and two Y columns. It is intended only for smoke-testing the Origin import and plotting path.

Example command on Windows:

```powershell
python .\tools\origin_batch_plot.py --input .\examples\origin_batch_plot_sample.csv --x-col 0 --y-col 1 --output .\examples\origin_batch_plot_sample.emf --plot-type l
```

This command requires OriginLab Origin and the `originpro` Python package. The CI workflow does not launch Origin; it only checks Python syntax for the public tools.
