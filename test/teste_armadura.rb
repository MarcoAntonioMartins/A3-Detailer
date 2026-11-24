# encoding: UTF-8
# Testa a planilha de armaduras (leitura, resumo de aço) e o desenho da
# armadura na prancha (Ruby puro).
require 'tmpdir'
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
A = Armadura
EXEMPLO = File.expand_path('../docs/armaduras_exemplo.csv', __dir__)

# ---------------------------------------------------------------- leitura
dados, erros = A.ler_arquivo(EXEMPLO)
itens = dados['PPF1'] || []
confere('exemplo da referência PPF1: 8 linhas sem erro', erros.empty? && itens.size == 8)
confere('tipos L e E', itens.count { |i| i[:tipo] == 'L' } == 4 && itens.count { |i| i[:tipo] == 'E' } == 4)
confere('vírgula decimal (12,5 e 871,5)', itens.any? { |i| i[:bitola] == 12.5 } && itens.any? { |i| i[:ini] == 871.5 })
confere('forma do estribo 20x45', itens.find { |i| i[:pos] == 'N5' }[:forma] == [20.0, 45.0])

# CSV salvo pelo Excel em português: Windows-1252, cabeçalho por extenso
txt = "Peça;Posição;Diâmetro;Quantidade;Comprimento;Tipo;Início;Fim;Espaçamento;Forma\r\n" \
      "Pç1;N1;10;4;300;L;;;;\r\n" \
      "Pç1;N2;5;;100;E;0;300;15;20x30\r\n"
Dir.mktmpdir do |dir|
  arq = File.join(dir, 'arm.csv')
  File.binwrite(arq, txt.encode('Windows-1252'))
  d2, e2 = A.ler_arquivo(arq)
  it2 = d2['PC1'] || []
  confere('CSV do Excel (Windows-1252, cabeçalho por extenso)', e2.empty? && it2.size == 2)
  confere('longitudinal sem INÍCIO/FIM: 0 até o comprimento', it2[0] && it2[0][:ini] == 0 && it2[0][:fim] == 300)
  confere('estribo sem QTD: calculado pelo trecho (300/15 + 1 = 21)', it2[1] && it2[1][:qtd] == 21)
end

_, e3 = A.ler("PECA;POS;BITOLA;QTD;COMP;TIPO\nP1;N1;x;2;100;L\nP1;N2;10;2;;L\nP1;N3;10;2;100;Z\n")
confere('erros com o número da linha', e3.size == 3 && e3[0].start_with?('linha 2') && e3[2].include?('TIPO'))
_, e4 = A.ler("PECA;BITOLA\nP1;10\n")
confere('cabeçalho incompleto é avisado', e4.size == 1 && e4[0].include?('POS'))

# ---------------------------------------------------------------- resumo
linhas, total78 = A.resumo(itens, 7800)
_, total785 = A.resumo(itens, 7850)
confere('resumo por posição, em ordem N1..N7', linhas.map { |g| g[:pos] } == %w[N1 N2 N3 N4 N5 N6 N7])
confere('N5 soma os dois trechos (4 + 48 = 52)', linhas.find { |g| g[:pos] == 'N5' }[:qtd] == 52)
confere('massa 7800: total ~118,33 kg da referência', (total78 - 118.33).abs < 0.1)
confere('massa 7850 (NBR 7480): 119,15 kg', (total785 - 119.15).abs < 0.01)
confere('Ø16 a 7850 kg/m³ = 1,578 kg/m', (A.massa_linear(16) - 1.578).abs < 0.001)

# ---------------------------------------------------------------- prancha
cfg = Apoio.cfg(massa_aco: 7800)
peca = Apoio.ppf1.merge(armadura: itens)
pr = Prancha.new(peca, cfg)
pr.gerar(File.join(SAIDA, pr.nome_arquivo + '-ARMADURA.pdf'))
g = Apoio::Grava.new
pg = Prancha.new(peca, cfg)
pg.desenhar(g)
ts = g.textos.map { |t| t[:s] }
arm = g.linhas.select { |ln| ln[4] == 'ARMADURA' }
confere('vistas continuam em 1:30 e cortes em 1:20 (como a referência)',
        pr.escala_vistas == 30 && pr.escala_cortes == 20)
confere('quadro "Resumo de aço" com total 118,39', ts.include?('RESUMO DE AÇO') && ts.include?('118,39'))
confere('coluna "Taxa de aço" no resumo da peça', ts.include?('Taxa de aço'))
confere('rótulos das barras ("2 N1 Ø16,0mm C=886")', ts.include?('2 N1 Ø16,0mm C=886') && ts.include?('3 N4 Ø12,5mm C=250'))
confere('trechos de estribos ("48 N5 c/15", "9 N6 c/15")', ts.include?('48 N5 c/15') && ts.include?('9 N6 c/15'))
confere('72 estribos desenhados (4 + 11 + 48 + 9)',
        arm.count { |x1, y1, x2, y2, _| (x1 - x2).abs < 1e-6 && (y2 - y1).abs > 4 } >= 72)
confere('formas dos 3 estribos', pg.escala_formas && %w[N5 N6 N7].all? { |n| ts.any? { |t| t.include?(" #{n} Ø5,0 C=") } })
confere('textos sem sobreposição', g.sobrepostos.empty?)
puts "      sobrepostos: #{g.sobrepostos.inspect}" unless g.sobrepostos.empty?
confere('tudo dentro da moldura', g.linhas.all? { |x1, y1, x2, y2, c| c == 'FOLHA' || [x1, x2].min >= 25 && [x1, x2].max <= 413 && [y1, y2].min >= 7 && [y1, y2].max <= 290 })

dxf = File.join(SAIDA, pr.nome_arquivo + '-ARMADURA.dxf')
Prancha.new(peca, cfg).gerar(dxf)
confere('DXF com a camada ARMADURA', File.binread(dxf).include?("8\r\nARMADURA\r\n"))

# pilar com dois consoles e laje (3D deitado) com armadura
csv2 = <<CSV
PEÇA;POS;BITOLA;QTD;COMP;TIPO;INÍCIO;FIM;ESPAC;FORMA
LAJE09;N1;10;8;675;L;2;677;;
LAJE09;N2;8;;120;E;0;679;20;19x105
PPF04;N1;16;4;1005;L;0;1005;;
PPF04;N2;12,5;4;450;L;509;959;;
PPF04;N3;6,3;;180;E;0;1010;15;34x34
PPF04;N4;8;6;200;E;509;554;9;59x24
CSV
d2, = A.ler(csv2)
[['PPF04', Apoio.ppf04, 30], ['LAJE09', Apoio.laje09, 30]].each do |nome, p, esc|
  pp = Prancha.new(p.merge(armadura: d2[nome]), Apoio.cfg)
  pp.gerar(File.join(SAIDA, pp.nome_arquivo + '-ARMADURA.pdf'))
  gg = Apoio::Grava.new
  Prancha.new(p.merge(armadura: d2[nome]), Apoio.cfg).desenhar(gg)
  tit = gg.textos.select { |t| t[:s] =~ /\ACORTE [A-Z]-[A-Z]\z/ }
  confere("#{nome} com armadura: vistas 1:#{esc}, cortes embaixo em 1:40 ou maior",
          pp.escala_vistas == esc && pp.escala_cortes <= 40 && tit.all? { |t| t[:y] < 125 })
  confere("#{nome} com armadura: textos sem sobreposição", gg.sobrepostos.empty?)
  puts "      sobrepostos: #{gg.sobrepostos.inspect}" unless gg.sobrepostos.empty?
end
tl = Apoio::Grava.new
Prancha.new(Apoio.ppf04.merge(armadura: d2['PPF04']), Apoio.cfg).desenhar(tl)
yt = lambda { |s| tl.textos.find { |t| t[:s] == s }[:y] }
confere('trechos sobrepostos (N3 na peça toda, N4 no console) em linhas separadas',
        (yt.call('68 N3 c/15') - yt.call('6 N4 c/9')).abs > 3)

sem = Prancha.new(Apoio.ppf1, cfg)
gs = Apoio::Grava.new
sem.desenhar(gs)
confere('sem planilha: prancha sem armadura nem taxa de aço',
        gs.linhas.none? { |ln| ln[4] == 'ARMADURA' } && !gs.textos.any? { |t| t[:s] == 'Taxa de aço' })

puts($falhas.zero? ? 'Todos os testes passaram.' : "#{$falhas} teste(s) falharam.")
exit($falhas.zero? ? 0 : 1)
