"""Render the chat app's Azure architecture with Diagrams and Graphviz.

From the repository root:
    .venv/bin/python docs/azure_architecture.py

The PNG is written next to this file. Coordinates and arrow routes are explicit
so changing Graphviz's automatic layout cannot move labels over icons or lines.
All coordinates are Graphviz points (72 points = one inch).
"""

from html import escape
from pathlib import Path

from diagrams import Cluster, Diagram
from diagrams.azure.compute import ContainerRegistries, KubernetesServices
from diagrams.azure.database import CosmosDb, DatabaseForPostgresqlServers
from diagrams.azure.identity import ManagedIdentities
from diagrams.azure.devops import Pipelines
from diagrams.azure.integration import APIConnections
from diagrams.azure.security import KeyVaults
from diagrams.azure.storage import BlobStorage
from diagrams.k8s.compute import Pod
from diagrams.k8s.network import Ingress
from diagrams.onprem.client import Users
from diagrams.onprem.inmemory import Redis
from diagrams.saas.cdn import Cloudflare


OUTPUT = Path(__file__).resolve().with_name("azure-architecture")
INK = "#475569"
BLUE = "#1677c8"
MUTED = "#8293a7"


class RoutedDiagram(Diagram):
    """Preserve point-based node, cluster, spline, and label positions."""

    def render(self):
        self.dot.engine = "neato"
        self.dot.render(format="png", neato_no_op=2, quiet=False)


def group(title, bounds, *, bottom=False, background="#edf6fc"):
    """Give each cluster a bounding box and an inset, left-aligned heading.

    Fixed-position Graphviz treats `lp` as a label's CENTER, even when
    labeljust='l'. A full-width HTML text node avoids clipped cluster headings.
    """
    left, low, right, high = bounds
    width = right - left - 40
    y = low + 24 if bottom else high - 24
    diagram.dot.node(
        "heading_" + str(left) + "_" + str(low),
        label=(f'<<TABLE BORDER="0" CELLBORDER="0" CELLPADDING="0" WIDTH="{width}">'
               f'<TR><TD ALIGN="LEFT">{escape(title)}</TD></TR></TABLE>>'),
        pos=f"{(left + right) / 2},{y}!", shape="plaintext",
        width="0", height="0", fixedsize="false", margin="0", fontsize="16", fontcolor="#1e293b",
    )
    return Cluster(title, graph_attr={
        "label": "",
        "bb": ",".join(map(str, bounds)),
        "bgcolor": background,
        "pencolor": "#b7cbdc",
        "penwidth": "1.1",
        "style": "rounded,filled",
    })


with RoutedDiagram(
    "",  # Intentionally no overall title/caption.
    filename=str(OUTPUT),
    show=False,
    graph_attr={
        "bgcolor": "white",
        "pad": "0.28",
        "margin": "0",
        "dpi": "180",
        "splines": "true",
        "outputorder": "edgesfirst",
        "fontname": "Arial",
    },
    node_attr={"fontname": "Arial", "fontsize": "14"},
    edge_attr={"fontname": "Arial", "fontsize": "13"},
) as diagram:

    def service(icon, name, x, y):
        # Separate, explicitly sized text nodes prevent the Diagrams icon's
        # fixed-size box from clipping long names or drawing text over images.
        node = icon("", pos=f"{x},{y}!", width="1", height="1", fixedsize="true")
        diagram.dot.node(
            node._id + "_name", label=name, pos=f"{x},{y - 55}!",
            shape="plaintext", fixedsize="false", width="0", height="0",
            margin="0", fontcolor="#1e293b",
        )
        return node

    def anchor(name, x, y):
        diagram.dot.node(name, label="", shape="point", width="0", height="0", pos=f"{x},{y}!")
        return name

    def route(source, target, points, text="", label_at=None, *, color=INK, dashed=False, arrow=True):
        """Draw an orthogonal polyline as explicit cubic Bezier segments.

        The label has its own fixed position in the adjacent whitespace; Graphviz
        must not guess either routing or label placement.
        """
        start, *rest = points
        controls = [start]
        previous = start
        for point in rest:
            controls.extend([previous, point, point])
            previous = point
        spline = " ".join(f"{x},{y}" for x, y in controls)
        if arrow:
            end_x, end_y = points[-1]
            prev_x, prev_y = points[-2]
            dx = 8 if end_x > prev_x else -8 if end_x < prev_x else 0
            dy = 8 if end_y > prev_y else -8 if end_y < prev_y else 0
            # Leave space for the arrowhead at the end of the final segment.
            controls[-2:] = [(end_x - dx, end_y - dy)] * 2
            spline = f"e,{end_x},{end_y} " + " ".join(f"{x},{y}" for x, y in controls)
        attrs = {
            "pos": spline,
            "color": color,
            "penwidth": "1.7" if color == BLUE else "1.2",
            "arrowsize": "0.7",
            "arrowhead": "normal" if arrow else "none",
            "style": "dashed" if dashed else "solid",
            "fontcolor": color,
        }
        if text:
            attrs.update(label=text, lp=f"{label_at[0]},{label_at[1]}")
        diagram.dot.edge(
            source._id if hasattr(source, "_id") else source,
            target._id if hasattr(target, "_id") else target,
            **attrs,
        )

    with group("AKS — chat namespace", (40, 500, 540, 880)):
        aks = service(KubernetesServices, "AKS", 130, 780)
        gateway = service(Ingress, "Gateway API", 130, 640)
        app = service(Pod, "chat-app", 450, 640)
        identity_target = anchor("identity_target", 130, 500)
        registry_target = anchor("registry_target", 290, 500)
        secrets_target = anchor("secrets_target", 450, 500)

    with group(
        "Identity, secrets, and image delivery", (40, 80, 540, 360), bottom=True,
    ):
        identity = service(ManagedIdentities, "Managed Identity", 130, 230)
        registry = service(ContainerRegistries, "Container Registry", 290, 230)
        vault = service(KeyVaults, "Key Vault", 450, 230)

    pipeline = service(Pipelines, "pipeline to be designed", 290, -70)
    pipeline_target = anchor("pipeline_target", 290, 80)

    with group("Azure data and application services", (740, 250, 1490, 880)):
        with group("data storage", (810, 470, 1470, 835), background="#dbeaf5"):
            postgres = service(DatabaseForPostgresqlServers, "PostgreSQL", 1050, 740)
            cosmos = service(CosmosDb, "Cosmos DB", 1050, 540)
            redis = service(Redis, "Managed Redis", 1360, 740)
            blobs = service(BlobStorage, "Blob Storage", 1360, 540)
        email = service(APIConnections, "Communication Services", 1050, 340)
        pubsub = service(APIConnections, "Web PubSub", 1360, 340)
        trunk = anchor("service_calls", 780, 640)

    # Cloudflare belongs between the client and AKS, not inside either group.
    domain = service(Cloudflare, "Cloudflare\nchat.nkdm.io", 820, 65)
    with group("Client", (1250, -35, 1490, 155)):
        user = service(Users, "User", 1360, 65)

    # The blue cycle is deliberately separate from infrastructure setup links.
    route(user, domain, [(1324, 65), (856, 65)], "1  Requests", (1090, 84), color=BLUE)
    route(domain, gateway,
          [(784, 65), (600, 65), (600, 565), (70, 565), (70, 640), (94, 640)],
          "Forward requests", (330, 548), color=BLUE)
    route(gateway, app, [(166, 640), (414, 640)], "UI / API requests", (290, 659), color=BLUE)

    # These app-to-service paths share a trunk, just like a conventional fan-out
    # diagram. Branch labels are placed on separate, unobstructed horizontal lanes.
    route(app, trunk, [(486, 640), (780, 640)], arrow=False)
    route(trunk, postgres, [(780, 640), (780, 740), (1014, 740)],
          "SQL queries / results", (895, 757))
    route(trunk, cosmos, [(780, 640), (780, 540), (1014, 540)],
          "Message reads / writes", (895, 557))
    route(trunk, blobs, [(780, 640), (1360, 640), (1360, 576)],
          "File uploads / downloads", (1205, 657))
    route(trunk, redis, [(780, 640), (780, 800), (1360, 800), (1360, 776)],
          "Presence / typing / rate limits", (1210, 817))
    route(trunk, email, [(780, 640), (780, 340), (1014, 340)],
          "Verification emails", (895, 357))
    route(trunk, pubsub, [(780, 640), (780, 440), (1360, 440), (1360, 376)],
          "2  Publish events", (1205, 457), color=BLUE)
    route(pubsub, user, [(1396, 340), (1450, 340), (1450, 125), (1360, 125), (1360, 101)],
          "3  WebSocket events\n(receive only)", (1330, 185), color=BLUE)

    # The planned pipeline manages this entire dependency group.
    route(pipeline, pipeline_target, [(290, -34), (290, 80)],
          "Manages", (337, 25), color=MUTED, dashed=True)

    # Setup arrows terminate at the AKS boundary instead of crossing app traffic.
    route(identity, identity_target, [(130, 266), (130, 500)],
          "Workload identity", (202, 425), color=MUTED, dashed=True)
    route(registry, registry_target, [(290, 266), (290, 500)],
          "Image pull", (335, 425), color=MUTED, dashed=True)
    route(vault, secrets_target, [(450, 266), (450, 500)],
          "Secrets", (483, 425), color=MUTED, dashed=True)
