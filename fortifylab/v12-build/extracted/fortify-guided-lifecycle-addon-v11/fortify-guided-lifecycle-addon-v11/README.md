# Guided Lab Lifecycle Add-on v11

Apply after toolkit v7 plus GitHub v8, recovery v9, and validation/fcli v10 add-ons:

```bash
./fortify-guided-lifecycle-addon-v11/apply-to-v7.sh ./fortify-lab-toolkit
cd fortify-lab-toolkit
./tests/run-tests.sh
../fortify-guided-lifecycle-addon-v11/tests/guided-static-test.sh .
sudo ./install.sh
sudo fortify-lab guided
```

The interface is attended. It preserves the strict workflow gates, durable resume state, manual `fortify.license` import, manual LIM licensing checkpoint, storage cleanup safeguards, and conservative boot/recovery behavior.
