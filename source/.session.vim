let SessionLoad = 1
if &cp | set nocp | endif
let s:so_save = &so | let s:siso_save = &siso | set so=0 siso=0
let v:this_session=expand("<sfile>:p")
silent only
silent tabonly
cd ~/th/code/ares/source
if expand('%') == '' && !&modified && line('$') <= 1 && getline(1) == ''
  let s:wipebuf = bufnr('%')
endif
set shortmess=aoO
badd +36 proc/mod/businessProcessModifier.d
badd +214 proc/sim/simulator.d
badd +43 proc/mod/assignMod.d
badd +36 proc/mod/moveMod.d
badd +35 proc/sim/pathFinder.d
badd +100 proc/businessProcess.d
badd +110 proc/businessProcessGenerator.d
badd +68 web/service.d
badd +159 ~/th/code/ares/public/js/site.js
badd +9 proc/epcElement.d
badd +1 graphviz/dotGenerator.d
badd +14 proc/event.d
badd +15 proc/func.d
badd +11 proc/gate.d
badd +43 proc/sim/multiple.d
badd +12 proc/businessProcessExamples.d
badd +66 config.d
badd +17 proc/mod/parallelizeMod.d
badd +150 proc/sim/runner.d
badd +18 proc/mod/modification.d
badd +43 app.d
argglobal
silent! argdel *
edit proc/mod/assignMod.d
set splitbelow splitright
wincmd t
set winminheight=0
set winheight=1
set winminwidth=0
set winwidth=1
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
let s:l = 112 - ((35 * winheight(0) + 19) / 39)
if s:l < 1 | let s:l = 1 | endif
exe s:l
normal! zt
112
normal! 0
lcd ~/th/code/ares/source
tabnext 1
if exists('s:wipebuf') && len(win_findbuf(s:wipebuf)) == 0
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
