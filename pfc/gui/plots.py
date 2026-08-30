from __future__ import annotations

import numpy as np
from matplotlib.backends.backend_qtagg import FigureCanvasQTAgg
from matplotlib.figure import Figure
from PySide6.QtWidgets import QSizePolicy, QVBoxLayout, QWidget

from pfc.experiment.runner import PulseUpdate


class PlotPanel(QWidget):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setMinimumSize(480, 220)
        self.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Expanding)
        self.fig = Figure(figsize=(10, 5.2), facecolor="#1b1e23", layout="constrained")
        self.fig.set_constrained_layout_pads(w_pad=0.10, h_pad=0.14, wspace=0.12, hspace=0.20)
        self.canvas = FigureCanvasQTAgg(self.fig)
        self.canvas.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Expanding)
        layout = QVBoxLayout(self)
        layout.setContentsMargins(4, 4, 4, 4)
        layout.addWidget(self.canvas)

        gs = self.fig.add_gridspec(2, 3, height_ratios=[1.2, 1.0])
        self.ax_sig = self.fig.add_subplot(gs[0, 0:2])
        self.ax_fft = self.fig.add_subplot(gs[0, 2])
        self.ax_sc = self.fig.add_subplot(gs[1, 0])
        self.ax_ic = self.fig.add_subplot(gs[1, 1])
        self.ax_v = self.fig.add_subplot(gs[1, 2])
        for ax in (self.ax_sig, self.ax_fft, self.ax_sc, self.ax_ic, self.ax_v):
            _style_ax(ax)

        self.line_sig, = self.ax_sig.plot([], [], color="#5dade2", lw=0.9)
        self.line_fft, = self.ax_fft.plot([], [], color="#58d68d", lw=0.9)
        self.ax_fft.set_yscale("log")
        self.line_sc, = self.ax_sc.plot([], [], ".", color="#5dade2", ms=4)
        self.line_ic, = self.ax_ic.plot([], [], ".", color="#af7ac5", ms=4)
        self.line_v, = self.ax_v.plot([], [], "o", color="#f4d03f", ms=3)

        self.ax_sig.set_title("Time Signal", pad=6)
        self.ax_sig.set_xlabel("Time (µs)")
        self.ax_sig.set_ylabel("Amplitude")
        self.ax_fft.set_title("FFT", pad=6)
        self.ax_fft.set_xlabel("Frequency (MHz)")
        self.ax_fft.set_xlim(0, 10)
        self.ax_sc.set_title("SC", pad=6)
        self.ax_ic.set_title("IC", pad=6)
        self.ax_v.set_title("Voltage", pad=6)
        for ax in (self.ax_sc, self.ax_ic, self.ax_v):
            ax.set_xlabel("Pulse #")

        self._n: list[int] = []
        self._sc: list[float] = []
        self._ic: list[float] = []
        self._v: list[float] = []

    def reset(self, xmax: float, vmax: float) -> None:
        self._n, self._sc, self._ic, self._v = [], [], [], []
        for line in (self.line_sig, self.line_fft, self.line_sc, self.line_ic, self.line_v):
            line.set_data([], [])
        for ax in (self.ax_sc, self.ax_ic, self.ax_v):
            ax.set_xlim(0, max(10.0, xmax))
        self.ax_v.set_ylim(0, max(10.0, vmax))
        self.canvas.draw_idle()

    def update_pulse(self, upd: PulseUpdate, vmax: float) -> None:
        self.line_sig.set_data(upd.t_us, upd.signal)
        self.ax_sig.relim()
        self.ax_sig.autoscale_view()
        y = np.clip(upd.fft_amp, 1e-18, None)
        self.line_fft.set_data(upd.freq_mhz, y)
        self.ax_fft.set_xlim(0, 10)
        self.ax_fft.relim()
        self.ax_fft.autoscale_view()
        self.ax_fft.set_ylim(bottom=max(float(y.min()) * 0.5, 1e-12))
        self._n.append(upd.pulse)
        self._sc.append(upd.sc)
        self._ic.append(upd.ic)
        self._v.append(upd.volt_mV)
        self.line_sc.set_data(self._n, self._sc)
        self.line_ic.set_data(self._n, self._ic)
        self.line_v.set_data(self._n, self._v)
        for ax, ys in ((self.ax_sc, self._sc), (self.ax_ic, self._ic)):
            ax.relim()
            ax.autoscale_view(scalex=False)
            if ys:
                ax.set_ylim(0, max(ys) * 1.15 + 1e-12)
        self.ax_v.set_ylim(0, max(vmax, max(self._v) * 1.1 if self._v else vmax))
        xmax = max(self._n[-1] + 2, self.ax_sc.get_xlim()[1])
        for ax in (self.ax_sc, self.ax_ic, self.ax_v):
            ax.set_xlim(0, xmax)
        self.canvas.draw_idle()


def _style_ax(ax) -> None:
    ax.set_facecolor("#121417")
    ax.tick_params(colors="#9aa3ad", labelsize=8, pad=2)
    ax.xaxis.label.set_color("#9aa3ad")
    ax.yaxis.label.set_color("#9aa3ad")
    ax.xaxis.label.set_fontsize(8)
    ax.yaxis.label.set_fontsize(8)
    ax.title.set_color("#d7dbe0")
    ax.title.set_fontsize(10)
    ax.title.set_fontweight("bold")
    for spine in ax.spines.values():
        spine.set_color("#3a404a")
    ax.grid(True, color="#2c313a", lw=0.5)
    ax.set_axisbelow(True)
