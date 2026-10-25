.PHONY: test test-x11 test-examples examples demo play-breaker play-orbit play-crater play-echo

test:
	SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy sbcl --no-userinit --script scripts/test.lisp

test-x11:
	SDL_VIDEODRIVER=x11 SDL_AUDIODRIVER=dummy PIXELISP_TEST_CLIPBOARD=1 PIXELISP_TEST_X11=1 xvfb-run -a sbcl --no-userinit --script scripts/test.lisp

test-examples:
	SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy sbcl --no-userinit --script scripts/test-examples.lisp

examples:
	sbcl --no-userinit --script scripts/example.lisp --list

demo: play-breaker

play-breaker:
	sbcl --no-userinit --script scripts/example.lisp prism-breaker

play-orbit:
	sbcl --no-userinit --script scripts/example.lisp orbit-patrol

play-crater:
	sbcl --no-userinit --script scripts/example.lisp crater-command

play-echo:
	sbcl --no-userinit --script scripts/example.lisp echo-grove
