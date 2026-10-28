(defpackage #:pixelisp
  (:use #:cl) (:nicknames #:px) (:shadow #:error)
  (:export #:init #:quit #:get-init #:with-init #:dispose #:with-resource
           #:error #:initialization-error #:dependency-error #:unsupported-feature
           #:disposed-resource #:resource-in-use #:operation #:message
           #:color #:make-color #:color-r #:color-g #:color-b #:color-a
           #:rect #:make-rect #:rect-x #:rect-y #:rect-width #:rect-height
           #:make-surface #:make-vector2 #:make-vector3 #:make-mask #:make-sprite #:make-group))

(defpackage #:pixelisp.internal
  (:use #:cl)
  (:export #:resource #:handle #:resource-disposed-p #:dispose #:ensure-live
           #:register-resource #:*resources* #:rgba #:pair #:as-rect #:native-error
           #:surface-handle #:wrap-surface #:write-surface-pixel #:%ptr #:*video-thread* #:check-video-thread
           #:*initialized* #:*shutdown-hooks* #:*pump-hooks* #:prepare-native-runtime
           #:with-native-context))

(defpackage #:pixelisp.rect
  (:use #:cl) (:nicknames #:px.rect) (:shadow #:union)
  (:export #:make-rect #:x #:y #:width #:height #:left #:top #:right #:bottom
           #:center #:size #:copy #:move #:move-ip #:inflate #:inflate-ip #:clip
           #:union #:union-all #:clamp #:normalize #:collide-point #:collide-rect
           #:collide-list #:collide-list-all #:contains #:fit #:clipline
           #:top-left #:top-right #:bottom-left #:bottom-right
           #:mid-top #:mid-left #:mid-bottom #:mid-right #:center-x #:center-y
           #:clamp-ip #:union-ip #:union-all-ip #:scale-by #:scale-by-ip
           #:collide-objects #:collide-objects-all #:collide-dict #:collide-dict-all
           #:update-rect))
(defpackage #:pixelisp.color
  (:use #:cl) (:nicknames #:px.color)
  (:export #:make-color #:r #:g #:b #:a #:normalize #:lerp #:to-list
           #:hsva #:hsla #:cmy #:correct-gamma
           #:parse #:to-integer #:update-color #:grayscale #:premul-alpha
           #:add #:subtract #:multiply #:floor-divide #:modulo #:invert #:i1i2i3))
(defpackage #:pixelisp.colordict
  (:use #:cl) (:nicknames #:px.colordict)
  (:export #:the-colors #:color-names #:lookup))
(defpackage #:pixelisp.surface
  (:use #:cl) (:nicknames #:px.surface)
  (:shadow #:fill)
  (:export #:surface #:make-surface #:width #:height #:size #:alpha-p #:get-size #:get-width #:get-height
           #:get-at #:set-at #:fill #:blit #:blits #:copy #:convert #:convert-alpha
           #:get-rect #:get-clip #:set-clip #:get-alpha #:set-alpha #:get-colorkey
           #:set-colorkey #:subsurface #:scroll #:lock #:unlock #:locked-p #:dispose
           #:with-surface #:get-bounding-rect #:premul-alpha
           #:get-parent #:get-abs-parent #:get-offset #:get-abs-offset
           #:map-rgb #:unmap-rgb #:get-at-mapped #:set-at-mapped
           #:get-palette #:get-palette-at #:set-palette #:set-palette-at
           #:get-pitch #:get-bitsize #:get-bytesize #:get-masks
           #:get-shifts #:get-losses #:get-blendmode #:get-buffer #:get-view
           #:set-rle #:rle-enabled-p #:must-lock-p #:get-locked))
;; Read-time package availability for the native-independent sprite system.
(defpackage #:pixelisp.mask (:use #:cl) (:nicknames #:px.mask)
  (:export #:from-surface #:overlap))
(defpackage #:pixelisp.buffer
  (:use #:cl) (:nicknames #:px.buffer #:pixelisp.bufferproxy #:px.bufferproxy)
  (:shadow #:close #:write)
  (:export #:buffer-view #:make-view #:view-ref #:dimensions #:strides #:byte-offset #:element-type
           #:owner #:closed-p #:close #:with-view #:slice #:to-array
           #:parent #:byte-length #:contiguous-p #:raw #:write #:write-bytes))
