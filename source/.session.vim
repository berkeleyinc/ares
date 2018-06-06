let SessionLoad = 1
if &cp | set nocp | endif
let s:so_save = &so | let s:siso_save = &siso | set so=0 siso=0
let v:this_session=expand("<sfile>:p")
silent only
cd ~/th/code/ares/source
if expand('%') == '' && !&modified && line('$') <= 1 && getline(1) == ''
  let s:wipebuf = bufnr('%')
endif
set shortmess=aoO
badd +34 proc/mod/businessProcessModifier.d
badd +82 proc/sim/simulator.d
badd +98 proc/mod/assignMod.d
badd +117 proc/mod/moveMod.d
badd +153 proc/sim/pathFinder.d
badd +164 proc/businessProcess.d
badd +38 ~/th/wip/gliederung
badd +14 proc/resource.d
badd +49 proc/businessProcessGenerator.d
badd +68 web/service.d
badd +159 ~/th/code/ares/public/js/site.js
badd +9 proc/epcElement.d
badd +29 graphviz/dotGenerator.d
badd +14 proc/event.d
badd +15 proc/func.d
badd +8 proc/gate.d
badd +43 proc/sim/multiple.d
badd +8 proc/businessProcessExamples.d
badd +66 config.d
badd +82 proc/mod/parallelizeMod.d
badd +17 proc/sim/runner.d
argglobal
silent! argdel *
edit proc/sim/multiple.d
set splitbelow splitright
wincmd t
set winminheight=1 winheight=1 winminwidth=1 winwidth=1
argglobal
setlocal fdm=manual
setlocal fde=0
setlocal fmr={{{,}}}
setlocal fdi=#
setlocal fdl=0
setlocal fml=1
setlocal fdn=20
setlocal fen
silent! normal! zE
let s:l = 64 - ((37 * winheight(0) + 20) / 41)
if s:l < 1 | let s:l = 1 | endif
exe s:l
normal! zt
64
normal! 07|
lcd ~/th/code/ares/source
tabnext 1
if exists('s:wipebuf') && s:wipebuf != bufnr('%')
  silent exe 'bwipe ' . s:wipebuf
endif
unlet! s:wipebuf
set winheight=1 winwidth=20 shortmess=filnxtToOc
set winminheight=1 winminwidth=1
let s:sx = expand("<sfile>:p:r")."x.vim"
if file_readable(s:sx)
  exe "source " . fnameescape(s:sx)
endif
let &so = s:so_save | let &siso = s:siso_save
doautoall SessionLoadPost
unlet SessionLoad
" vim: set ft=vim :
