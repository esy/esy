test::
	@./node_modules/.bin/jest

watch::
	@./node_modules/.bin/jest --watch

shell::
	@./node_modules/.bin/babel-node \
		--plugins transform-object-rest-spread \
		./shell.js $(DEPENDENCIES)
