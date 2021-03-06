.PHONY: boot

test:
	vagrant up
	bash test.sh || (echo "bash test.sh failed $$?"; exit 1)
	vagrant destroy

# if you vagrant halt -> then vagrant up
# you MUST make boot afterwards to get everything spun up again
boot:
	vagrant up
	vagrant ssh node1 -c "sudo bash /vagrant/install.sh boot" || true
	vagrant ssh node2 -c "sudo bash /vagrant/install.sh boot" || true
	vagrant ssh master -c "sudo bash /vagrant/install.sh boot master" || true