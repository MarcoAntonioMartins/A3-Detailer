# encoding: UTF-8
# Peças de teste geradas em Ruby puro (sem SketchUp).
SRC = File.expand_path('../src/detalhamento_pm', __dir__) unless defined?(SRC)
SAIDA = File.expand_path('saida', __dir__) unless defined?(SAIDA)
Dir.mkdir(SAIDA) unless Dir.exist?(SAIDA)

module Apoio
  module_function

  # Sólido formado por caixas cheias menos caixas vazias ([x0,x1,y0,y1,z0,z1], mm).
  # Gera triângulos e só as arestas de quina (como o SketchUp, sem arestas
  # entre faces coplanares).
  def malha(cheias, vazias = [])
    todas = cheias + vazias
    xs = todas.flat_map { |b| [b[0], b[1]] }.uniq.sort
    ys = todas.flat_map { |b| [b[2], b[3]] }.uniq.sort
    zs = todas.flat_map { |b| [b[4], b[5]] }.uniq.sort
    dentro = lambda do |c, lista|
      lista.any? do |b|
        c[0] > b[0] && c[0] < b[1] && c[1] > b[2] && c[1] < b[3] && c[2] > b[4] && c[2] < b[5]
      end
    end
    cel = {}
    (0...xs.size - 1).each do |i|
      (0...ys.size - 1).each do |j|
        (0...zs.size - 1).each do |k|
          c = [(xs[i] + xs[i + 1]) / 2.0, (ys[j] + ys[j + 1]) / 2.0, (zs[k] + zs[k + 1]) / 2.0]
          cel[[i, j, k]] = true if dentro.call(c, cheias) && !dentro.call(c, vazias)
        end
      end
    end
    quads = []
    cel.each_key do |i, j, k|
      x0, x1, y0, y1, z0, z1 = xs[i], xs[i + 1], ys[j], ys[j + 1], zs[k], zs[k + 1]
      quads << [[[x0, y0, z0], [x0, y0, z1], [x0, y1, z1], [x0, y1, z0]], [-1, 0, 0]] unless cel[[i - 1, j, k]]
      quads << [[[x1, y0, z0], [x1, y1, z0], [x1, y1, z1], [x1, y0, z1]], [1, 0, 0]] unless cel[[i + 1, j, k]]
      quads << [[[x0, y0, z0], [x1, y0, z0], [x1, y0, z1], [x0, y0, z1]], [0, -1, 0]] unless cel[[i, j - 1, k]]
      quads << [[[x0, y1, z0], [x0, y1, z1], [x1, y1, z1], [x1, y1, z0]], [0, 1, 0]] unless cel[[i, j + 1, k]]
      quads << [[[x0, y0, z0], [x0, y1, z0], [x1, y1, z0], [x1, y0, z0]], [0, 0, -1]] unless cel[[i, j, k - 1]]
      quads << [[[x0, y0, z1], [x1, y0, z1], [x1, y1, z1], [x0, y1, z1]], [0, 0, 1]] unless cel[[i, j, k + 1]]
    end
    tris = []
    inc = Hash.new { |h, k| h[k] = [] }
    quads.each do |q, n|
      tris << [q[0], q[1], q[2]] << [q[0], q[2], q[3]]
      4.times { |m| inc[[q[m], q[(m + 1) % 4]].sort] << n }
    end
    [tris, inc.select { |_, ns| ns.uniq.size > 1 }.keys]
  end

  def alca(z)
    x = 125.0
    pts = [[x, 350, z - 30], [x, 600, z - 30], [x, 600, z + 30], [x, 350, z + 30]]
    (0...3).map { |k| [pts[k], pts[k + 1]] }
  end

  # Pilar parecido com o PPF1: 25x50, 998,5 cm, rebaixo no topo e dentes laterais.
  def ppf1
    l = 9985.0
    tris, arestas = malha([[0, 250, 0, 500, 0, 8715], [0, 250, 0, 250, 8715, l]],
                          [[-1, 30, 80, 180, 1190, l + 1], [220, 251, 80, 180, 1190, l + 1]])
    { nome: 'PPF1', tag: '2. Pilares', tipo: 'PILAR', tipo_plural: 'PILARES', qtd: 11,
      tris: tris, arestas: arestas,
      insertos: [{ nome: 'Alça de içamento', arestas: alca(2200) },
                 { nome: 'Alça de içamento', arestas: alca(7200) }] }
  end

  # Viga simples 20x60x600 cm deitada ao longo de x.
  def viga
    tris, arestas = malha([[0, 6000, 0, 200, 0, 600]])
    { nome: 'V1', tag: '5. Vigas', tipo: 'VIGA', tipo_plural: 'VIGAS', qtd: 6,
      tris: tris, arestas: arestas, insertos: [] }
  end

  def cfg(extra = {})
    { obra: 'EDIFICAÇÃO COMERCIAL', local: '-', prefixo: 'EC', codigo: 'TESTE',
      revisao: '01', revisoes: ['00 - EMISSÃO INICIAL', '01 - ALTERAÇÃO DA QUANTIDADE (12 -> 11)'],
      data: '02/11/2026', fck: 40, peso_esp: 2.5, fonte: 'romans.shx', formato: 0,
      tags: [], insertos: %w[alça inserto] }.merge(extra)
  end
end
