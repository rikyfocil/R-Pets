.PHONY: install remove

install:
	swift build -c release --product RPetsMCP
	python3 .claude/hooks/install.py install

remove:
	python3 .claude/hooks/install.py remove
