## How to run on local machine

    # tmt run -vvvvv plans -n bootc-install

## How to run on Testing Farm

```shell
testing-farm request \
    --plan bootc-install \
    --git-ref main \
    --git-url https://github.com/henrywang/tmt-bootc-install-switch.git \
    --compose Fedora-41 \
    --arch x86_64
```

Artifacts: https://artifacts.osci.redhat.com/testing-farm/d88be6ff-2281-4f49-9cdf-e8dc7a62fde9/
