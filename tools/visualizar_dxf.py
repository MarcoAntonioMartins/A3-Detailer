import sys
import ezdxf
from ezdxf.addons.drawing import RenderContext, Frontend
from ezdxf.addons.drawing.matplotlib import MatplotlibBackend
from ezdxf.addons.drawing.config import Configuration, BackgroundPolicy
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

doc = ezdxf.readfile(sys.argv[1])
aud = doc.audit()
print("erros auditoria:", len(aud.errors), "corrigidos:", len(aud.fixes))
msp = doc.modelspace()
print("entidades:", len(msp))
fig = plt.figure(figsize=(16.5, 11.7))
ax = fig.add_axes([0, 0, 1, 1])
ctx = RenderContext(doc)
ctx.set_current_layout(msp)
Frontend(ctx, MatplotlibBackend(ax), config=Configuration(background_policy=BackgroundPolicy.WHITE)).draw_layout(msp, finalize=True)
ax.set_facecolor("white")
fig.patch.set_facecolor("white")
if len(sys.argv) > 3:
    x0, y0, x1, y1 = map(float, sys.argv[3].split(","))
    ax.set_xlim(x0, x1); ax.set_ylim(y0, y1)
fig.savefig(sys.argv[2], dpi=int(sys.argv[4]) if len(sys.argv) > 4 else 110, facecolor="white")
