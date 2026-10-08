# Fortify Lab v12 Builder

This archive extracts to the `fortifylab` directory.

## Extract the builder

```bash
tar -xzf fortifylab.tar.gz
cd fortifylab
./build-v12.sh
```

Then place exactly one archive format for each required input directly in `fortifylab/`:

```text
fortify-lab-toolkit-v7.zip or .tar.gz
fortify-github-addon-v8.zip or .tar.gz
fortify-recovery-addon-v9.zip or .tar.gz
fortify-validation-addon-v10.zip or .tar.gz
fortify-guided-lifecycle-addon-v11.zip or .tar.gz
```

Run:

```bash
cd fortifylab
./build-v12.sh
```

The builder searches its own `fortifylab` directory, supports mixed ZIP/TAR.GZ inputs, rejects missing packages and duplicate formats, validates each archive and expected root directory, runs builder/toolkit tests, and writes final artifacts to `fortifylab/dist/`.
