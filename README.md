## How to run on local machine

    # tmt run -vvvvv plans -n bootc-install

## How to run on Testing Farm

    # testing-farm request --plan bootc-install --git-ref main --git-url https://github.com/henrywang/tmt-bootc-install-switch.git --compose Fedora-41 --arch x86_64
