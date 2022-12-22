SHELL := /bin/bash

tf-fmt:
	@terraform fmt -recursive

tf-validate:
	@terraform validate

git-check:
	git status -uno .
	@if [ $$(git rev-parse HEAD) = $$(git rev-parse main@{upstream}) ]; then echo "Git Status: OK"; else echo "Git Status: Out-of-Sync" && exit 1; fi

# make git m="<commit-message>"
git: git-check tf-fmt
	@git add .
	@git commit -m "[terraform-azurerm-vm-linux] by $${USER^}" -m "${m}"
	@git push -u origin main
