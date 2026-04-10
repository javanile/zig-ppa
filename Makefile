
requirements:
	@sudo apt install debhelper dpkg-dev devscripts

push:
	@git config credential.helper 'cache --timeout=3600'
	@git add .
	@git commit -am fix
	@git push