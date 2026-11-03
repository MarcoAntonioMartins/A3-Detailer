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
