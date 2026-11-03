# encoding: UTF-8
# Gravador DXF R12 (AC1009) mínimo: linhas e textos. Abre no AutoCAD,
# BricsCAD, LibreCAD, DraftSight etc. Unidades do desenho: mm de papel.
module DetalhamentoPM
  class DXF
    # nome => [cor ACI, tipo de linha]
    CAMADAS = {
      'FOLHA'    => [7, 'CONTINUOUS'],
      'CARIMBO'  => [7, 'CONTINUOUS'],
      'CONTORNO' => [7, 'CONTINUOUS'],
      'OCULTO'   => [8, 'OCULTA'],
      'COTAS'    => [3, 'CONTINUOUS'],
      'TEXTO'    => [7, 'CONTINUOUS'],
      'HACHURA'  => [8, 'CONTINUOUS'],
      'INSERTOS' => [6, 'CONTINUOUS'],
      'CORTE'    => [1, 'CONTINUOUS'],
      'MODELO3D' => [7, 'CONTINUOUS']
    }.freeze

    def initialize(fonte = 'romans.shx')
      @fonte = fonte
      @ents = []
    end

    def f(v)
      format('%.4f', v.to_f)
    end

    def line(x1, y1, x2, y2, camada)
      @ents << "0\nLINE\n8\n#{camada}\n10\n#{f(x1)}\n20\n#{f(y1)}\n30\n0.0\n" \
               "11\n#{f(x2)}\n21\n#{f(y2)}\n31\n0.0\n"
    end

    # alinhamento: 0 = esquerda, 1 = centro, 2 = direita
    def text(s, x, y, h, camada, alinh = 0, rot = 0)
      s = s.to_s.gsub(/[\r\n]+/, ' ')
      e = "0\nTEXT\n8\n#{camada}\n10\n#{f(x)}\n20\n#{f(y)}\n30\n0.0\n" \
          "40\n#{f(h)}\n1\n#{s}\n50\n#{f(rot)}\n7\nSTANDARD\n"
      e += "72\n#{alinh}\n11\n#{f(x)}\n21\n#{f(y)}\n31\n0.0\n" if alinh != 0
      @ents << e
    end

    def conteudo
      o = +''
      o << "0\nSECTION\n2\nHEADER\n"
      o << "9\n$ACADVER\n1\nAC1009\n"
      o << "9\n$DWGCODEPAGE\n3\nANSI_1252\n"
      o << "9\n$INSBASE\n10\n0.0\n20\n0.0\n30\n0.0\n"
      o << "9\n$EXTMIN\n10\n0.0\n20\n0.0\n30\n0.0\n"
      o << "9\n$EXTMAX\n10\n420.0\n20\n297.0\n30\n0.0\n"
      o << "9\n$LIMMIN\n10\n0.0\n20\n0.0\n"
      o << "9\n$LIMMAX\n10\n420.0\n20\n297.0\n"
      o << "9\n$LTSCALE\n40\n1.0\n"
      o << "0\nENDSEC\n"

      o << "0\nSECTION\n2\nTABLES\n"
      o << "0\nTABLE\n2\nLTYPE\n70\n2\n"
      o << "0\nLTYPE\n2\nCONTINUOUS\n70\n0\n3\nSolid line\n72\n65\n73\n0\n40\n0.0\n"
      o << "0\nLTYPE\n2\nOCULTA\n70\n0\n3\n__ __ __\n72\n65\n73\n2\n40\n2.25\n" \
           "49\n1.5\n49\n-0.75\n"
      o << "0\nENDTAB\n"
      o << "0\nTABLE\n2\nLAYER\n70\n#{CAMADAS.size}\n"
      CAMADAS.each do |nome, (cor, lt)|
        o << "0\nLAYER\n2\n#{nome}\n70\n0\n62\n#{cor}\n6\n#{lt}\n"
      end
      o << "0\nENDTAB\n"
      o << "0\nTABLE\n2\nSTYLE\n70\n1\n"
      o << "0\nSTYLE\n2\nSTANDARD\n70\n0\n40\n0.0\n41\n0.8\n50\n0.0\n71\n0\n" \
           "42\n2.5\n3\n#{@fonte}\n4\n\n"
      o << "0\nENDTAB\n"
      o << "0\nENDSEC\n"

      o << "0\nSECTION\n2\nBLOCKS\n0\nENDSEC\n"
      o << "0\nSECTION\n2\nENTITIES\n"
      @ents.each { |e| o << e }
      o << "0\nENDSEC\n0\nEOF\n"
      o
    end

    def salvar(caminho)
      dados = conteudo.gsub("\n", "\r\n")
      dados = dados.encode('Windows-1252', invalid: :replace, undef: :replace, replace: '?')
      File.open(caminho, 'wb') { |io| io.write(dados) }
    end
  end
end
