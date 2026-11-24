# encoding: UTF-8
# Testa geometria, cortes automáticos e geração de PDF/DXF (Ruby puro).
require_relative 'apoio'
require File.join(SRC, 'geom')
require File.join(SRC, 'dxf')
require File.join(SRC, 'pdf')
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
