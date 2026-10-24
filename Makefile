.PHONY: test test-x11 test-examples examples demo demo-sprites demo-masks demo-images demo-ui demo-pixels

test:
	SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy sbcl --no-userinit --script scripts/test.lisp

test-x11:
	SDL_VIDEODRIVER=x11 SDL_AUDIODRIVER=dummy PIXELISP_TEST_CLIPBOARD=1 PIXELISP_TEST_X11=1 xvfb-run -a sbcl --no-userinit --script scripts/test.lisp

test-examples:
	SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy sbcl --no-userinit --script scripts/test-examples.lisp

examples:
	sbcl --no-userinit --script scripts/example.lisp --list

demo:
	sbcl --no-userinit --script scripts/play.lisp

demo-sprites:
	sbcl --no-userinit --script scripts/example.lisp sprite-lab

demo-masks:
	sbcl --no-userinit --script scripts/example.lisp mask-lab

demo-images:
	sbcl --no-userinit --script scripts/example.lisp image-lab

demo-ui:
	sbcl --no-userinit --script scripts/example.lisp ui-lab

demo-pixels:
	sbcl --no-userinit --script scripts/example.lisp pixel-lab
