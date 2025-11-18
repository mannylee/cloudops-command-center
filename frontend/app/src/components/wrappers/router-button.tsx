import { Button, ButtonProps } from "@cloudscape-design/components";
import { useNavigate } from "react-router-dom";

interface RouterButtonProps extends ButtonProps {
    href: string;
}

export default function RouterButton({ href, onClick, ...props }: RouterButtonProps) {
    const navigate = useNavigate();

    const handleClick = (event: any) => {
        if (onClick) {
            onClick(event);
        }
        navigate(href);
    };

    return <Button {...props} onClick={handleClick} />;
}