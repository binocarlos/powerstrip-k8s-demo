.PHONY: build

build:
	rm -rf package.box
	vagrant destroy -f
	vagrant up
	vagrant ssh -c "sudo bash /vagrant/install.sh"
	#vagrant package