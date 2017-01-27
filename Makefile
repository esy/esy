convert-opam-packages:
	@$(MAKE) -C opam-packages-conversion/ convert
	@rm -rf opam-packages/
	@mv opam-packages-conversion/output opam-packages
