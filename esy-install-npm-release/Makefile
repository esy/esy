install:
	@yarn

build: esyInstallNpmRelease.build.js

esyInstallNpmRelease.build.js: esyInstallNpmRelease.js
	@./node_modules/.bin/browserify           \
		--transform [                           \
				babelify --presets [                \
					@babel/preset-env                 \
						--targets.node "4.0.0"          \
					]                                 \
			]                                     \
		--node $(<)                             \
		--outfile $(@)
