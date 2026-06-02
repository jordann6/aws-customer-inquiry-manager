from diagrams import Diagram, Cluster, Edge
from diagrams.aws.network import APIGateway
from diagrams.aws.compute import Lambda
from diagrams.aws.database import Dynamodb
from diagrams.aws.engagement import SES
from diagrams.aws.security import IAM

graph_attrs = {
    "fontsize": "13",
    "bgcolor": "white",
    "pad": "0.5",
    "splines": "ortho",
}

node_attrs = {
    "fontsize": "11",
}

with Diagram(
    "AWS Customer Inquiry Manager",
    filename="docs/architecture",
    outformat="png",
    show=False,
    direction="LR",
    graph_attr=graph_attrs,
    node_attr=node_attrs,
):
    apigw = APIGateway("API Gateway v2\nPOST /inquiries\nGET /inquiries\nGET /inquiries/{id}\nPATCH /inquiries/{id}/status")

    with Cluster("AWS · us-east-1"):
        fn = Lambda("Lambda\ninquiry-api")
        role = IAM("IAM Execution Role\nDynamoDB + SES SendEmail")

        with Cluster("DynamoDB · inquiry-dev"):
            db = Dynamodb("Inquiries Table\nstatus-index GSI\nPAY_PER_REQUEST · PITR")

        email = SES("Amazon SES\nSupport Alert\n+ Customer Confirmation")

    apigw >> Edge(label="HTTP proxy") >> fn
    fn >> Edge(label="assumes") >> role
    role >> Edge(label="PutItem / GetItem\nQuery (status-index)") >> db
    role >> Edge(label="SendEmail\n(ses:FromAddress scoped)") >> email
