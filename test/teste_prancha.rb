# encoding: UTF-8
# Testa geometria, cortes automáticos e geração de PDF/DXF (Ruby puro).
require_relative 'apoio'
require File.join(SRC, 'geom')
require File.join(SRC, 'dxf')
require File.join(SRC, 'pdf')
require File.join(SRC, 'armadura')
require File.join(SRC, 'prancha')

$falhas = 0
def confere(desc, ok)
  puts "#{ok ? 'OK   ' : 'FALHA'} #{desc}"
  $falhas += 1 unless ok
end

include DetalhamentoPM

peca = Apoio.ppf1
confere('volume do PPF1 ~ 1,12 m³', (G.volume(peca[:tris]) / 1e9 - 1.116).abs < 0.002)

pr = Prancha.new(peca, Apoio.cfg)
pdf = pr.gerar(File.join(SAIDA, pr.nome_arquivo + '.pdf'))
confere('nome do arquivo no padrão', pr.nome_arquivo == 'EC-TESTE-DET-PPF1-R01')
confere('escala das vistas 1:30', pr.escala_vistas == 30)
confere('3 cortes (A, B, C)', pr.cortes.map { |c| c[:letra] } == %w[A B C])
confere('PDF gravado', File.binread(pdf, 5) == '%PDF-')

dxf = File.join(SAIDA, pr.nome_arquivo + '.dxf')
Prancha.new(peca, Apoio.cfg).gerar(dxf)
conteudo = File.binread(dxf)
confere('DXF R12 gravado', conteudo.include?('AC1009') && conteudo.end_with?("EOF\r\n"))

pv = Prancha.new(Apoio.viga, Apoio.cfg)
pv.gerar(File.join(SAIDA, pv.nome_arquivo + '.pdf'))
confere('viga sem variação de seção tem 1 corte', pv.cortes.size == 1)

# Laje parecida com a LAJE09: cotas pequenas, recortes e nomes das vistas
laje = Apoio.laje09
pl = Prancha.new(laje, Apoio.cfg)
pl.gerar(File.join(SAIDA, pl.nome_arquivo + '.pdf'))
g = Apoio::Grava.new
Prancha.new(laje, Apoio.cfg).desenhar(g)
cotas = g.cotas.map { |t| t[:s] }
conta = lambda { |s| cotas.count(s) }
confere('LAJE09: escala das vistas 1:20', pl.escala_vistas == 20)
confere('LAJE09: cadeia horizontal com os trechos pequenos (4 e 18)',
        conta.call('4') >= 2 && conta.call('18') >= 2)
confere('LAJE09: cadeia vertical completa (92,7 / 15 / 5)',
        %w[92,7 15 5].all? { |s| cotas.include?(s) })
confere('LAJE09: cota local do dente na ponta (5 cm)', conta.call('5') >= 2)
confere('LAJE09: cota local do recorte D (20 cm)', cotas.include?('20'))
confere('LAJE09: cota local do rebaixo da espessura (10 cm)', conta.call('10') >= 2)
confere('LAJE09: textos de cota sem sobreposição', g.sobrepostos.empty?)
puts "      sobrepostos: #{g.sobrepostos.inspect}" unless g.sobrepostos.empty?
ty = lambda { |gr, s| gr.textos.find { |t| t[:s] == s }[:y] }
confere('LAJE09: face grande (L x B) chamada de VISTA SUPERIOR',
        ty.call(g, 'VISTA SUPERIOR') < ty.call(g, 'VISTA LATERAL'))
gp = Apoio::Grava.new
Prancha.new(Apoio.ppf1, Apoio.cfg).desenhar(gp)
confere('PILAR mantém VISTA SUPERIOR = L x A (em cima)',
        ty.call(gp, 'VISTA SUPERIOR') > ty.call(gp, 'VISTA LATERAL'))
confere('PPF1: textos de cota sem sobreposição', gp.sobrepostos.empty?)
confere('PPF1: rótulos das alças fora da peça', gp.rotulos_sobre_peca.empty?)

# PPF04 simulado (pilar em pé com consoles, como a prancha real de 12/11/2026)
p4 = Apoio.ppf04
pr4 = Prancha.new(p4, Apoio.cfg)
pr4.gerar(File.join(SAIDA, pr4.nome_arquivo + '.pdf'))
g4 = Apoio::Grava.new
pr4b = Prancha.new(p4, Apoio.cfg)
pr4b.desenhar(g4)
confere('PPF04: dimensões 65 x 70 x 1010', g4.textos.any? { |t| t[:s] == '1010' })
confere('PPF04: vistas em 1:30 (eram 1:40 com a coluna 3D larga)', pr4.escala_vistas == 30)
confere('PPF04: 5 cortes em 1:25 ou maior', pr4.cortes.size == 5 && pr4.escala_cortes <= 25)
titulos_embaixo = lambda do |gr|
  ts = gr.textos.select { |t| t[:s] =~ /\ACORTE [A-Z]-[A-Z]\z/ }
  !ts.empty? && ts.all? { |t| t[:y] < 90 }
end
confere('PPF04: cortes embaixo, à esquerda do carimbo (como no padrão)', titulos_embaixo.call(g4))
confere('LAJE09: cortes embaixo e em escala legível (1:25)',
        titulos_embaixo.call(g) && pl.escala_cortes <= 25)
confere('PPF04: console saliente não vira "recorte" no resto da peça',
        pr4b.recortes.all?(&:empty?))
confere('PPF04: rótulos dos neoprenes fora da peça', g4.rotulos_sobre_peca.empty?)
puts "      sobre a peça: #{g4.rotulos_sobre_peca.inspect}" unless g4.rotulos_sobre_peca.empty?
confere('PPF04: rótulos dos dois neoprenes',
        %w[NP\ 15X25CM NP\ 10X20CM].all? { |n| g4.rotulos.any? { |t| t[:s] == n } })
confere('PPF04: textos sem sobreposição', g4.sobrepostos.empty?)
puts "      sobrepostos: #{g4.sobrepostos.inspect}" unless g4.sobrepostos.empty?
faixa = lambda { |c, k| v = c[:segs].flatten(1).map { |q| q[k] }; v.max - v.min }
confere('PPF04: um corte mostra o console para cima (seção com 70 cm)',
        pr4.cortes.any? { |c| faixa.call(c, 1) > 600 })
confere('PPF04: um corte mostra o console lateral (seção com 65 cm)',
        pr4.cortes.any? { |c| faixa.call(c, 0) > 600 })

# Com mais seções do que vagas, os consoles curtos não podem ficar de fora.
ret = lambda do |a0, a1, b0, b1|
  [[[a0, b0], [a1, b0]], [[a1, b0], [a1, b1]], [[a1, b1], [a0, b1]], [[a0, b1], [a0, b0]]]
end
secoes = [[400, 0, 400, 0, 400, 9000],      # fuste (principal)
          [100, 0, 400, 100, 400, 830],     # base
          [101, 0, 400, 0, 400, 470],       # transições sem saliência
          [102, 0, 400, 0, 400, 400], [103, 0, 400, 0, 400, 300],
          [104, 0, 400, 0, 400, 200], [105, 0, 400, 0, 400, 150],
          [106, 0, 400, 0, 700, 120],       # console para cima (curto)
          [107, 0, 650, 0, 400, 100]]       # console lateral (o mais curto)
unicos = secoes.each_with_index.map do |(id, a0, a1, b0, b1, comp), k|
  { sig: id, pos: k * 1000.0, segs: ret.call(a0, a1, b0, b1), comp: comp }
end
esc = pr4.send(:escolher_cortes, unicos).map { |u| u[:sig] }
confere('escolha de cortes: máx. 6, com o fuste e os dois consoles',
        esc.size == 6 && ([400, 106, 107] - esc).empty?)

# PPF04 de 25x50 com frisos chanfrados (prancha real de 24/11/2026)
cfg1 = Apoio.cfg(revisoes: ['00 - EMISSÃO INICIAL'], revisao: '00')
pf = Prancha.new(Apoio.ppf04_friso, cfg1)
pf.gerar(File.join(SAIDA, pf.nome_arquivo + '.pdf'))
gf = Apoio::Grava.new
Prancha.new(Apoio.ppf04_friso, cfg1).desenhar(gf)
cf = gf.cotas.map { |t| t[:s] }
confere('PPF04B: chanfros de 1 cm fora das cotas (nenhum "1")', !cf.include?('1'))
confere('PPF04B: friso cotado pela abertura (10) nos 3 cortes e na vista lateral',
        cf.count('10') >= 4)
confere('PPF04B: cortes em 1:10, embaixo', pf.escala_cortes == 10 && titulos_embaixo.call(gf))
confere('PPF04B: textos sem sobreposição', gf.sobrepostos.empty?)

confere('LAJE09: recortes reais continuam (dente e recorte D)',
        Prancha.new(laje, Apoio.cfg).desenhar(Apoio::Grava.new).recortes.flatten(1).size >= 3)

# PDF com várias páginas
doc = PDF.new
[Apoio.ppf1, Apoio.viga].each do |p|
  doc.nova_pagina
  Prancha.new(p, Apoio.cfg).desenhar(doc)
end
multi = doc.salvar(File.join(SAIDA, 'varias_paginas.pdf'))
confere('PDF com 2 páginas', File.binread(multi).include?('/Count 2'))

puts($falhas.zero? ? 'Todos os testes passaram.' : "#{$falhas} teste(s) falharam.")
exit($falhas.zero? ? 0 : 1)
