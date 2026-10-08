# Git and GitHub add-on for Fortify Toolkit v7

Apply to an extracted v7 toolkit:

```bash
unzip fortify-lab-toolkit-v7.zip
./fortify-github-addon-v8/apply-to-v7.sh ./fortify-lab-toolkit
cd fortify-lab-toolkit
./tests/run-tests.sh
```

Then install normally. Git and official GitHub CLI become prerequisites. Repository operations are optional via `fortify-lab repo ...`. GitHub Desktop remains optional and uses the community Shiftkey Linux fork because GitHub does not provide an official Linux build.
